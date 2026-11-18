# A scope: a member overridden with overrideScope (e.g. a variant's, through
# `variants`) reaches signedFirmware, bup and mkRcm.
{ lib, pkgs, newScope, cfg, jetpack, dtbsDir }@args:
lib.makeScope newScope (self:
let
  # The members, not the arguments, so an overrideScope of them reaches everything.
  inherit (self) cfg jetpack dtbsDir;

  # flash.sh's board spec: BOARDID-FAB-BOARDSKU-BOARDREV-fuselevel-CHIPREV-board-.
  boardSpec = v: chiprev: board:
    "${v.boardid}-${v.fab}-${v.boardsku}-${v.boardrev}-${if v.fuselevel == "fuselevel_production" then "1" else "0"}-${chiprev}-${board}-";
  variantKey = v: boardSpec v v.chiprev "";
  variantKeys = map variantKey cfg.firmware.variants;
  # flash-from-device selects by board spec, not CHIP_SKU or RAMCODE; a
  # duplicate would overwrite a distinct flash.sh run in every keyed set.
  uniqueVariants = lib.assertMsg (builtins.length variantKeys == builtins.length (lib.unique variantKeys))
    "decomposedFirmware: firmware.variants contains duplicate board specs: ${toString variantKeys}";

  leaves = self.callPackage ./leaves.nix { };
  variantArgs = {
    inherit lib pkgs cfg jetpack dtbsDir boardSpec variantKey;
    inherit (leaves) sign;
    inherit (self) variants;
  };
  mkVariant = v: lib.makeScope self.newScope (import ./variant.nix variantArgs v);
in
{
  inherit (args) cfg jetpack dtbsDir;
  inherit (leaves) common;

  variants = assert uniqueVariants;
    lib.listToAttrs (map (v: lib.nameValuePair (variantKey v) (mkVariant v)) cfg.firmware.variants);
  # In firmware.variants order.
  variantsList = map (v: self.variants.${variantKey v}) cfg.firmware.variants;
  defaultColdboot = (builtins.head self.variantsList).reference;

  signedFirmware = self.callPackage ./signed-firmware.nix { };
  bup = self.callPackage ./bup-payload.nix { };

  inherit (self.callPackage ./rcm-detect.nix {
    inherit (builtins.head self.variantsList) fuselevel;
    chipskus = lib.mapAttrs (_: v: v.chipsku) self.variants;
  }) rcmDetect mkRcmDetectVariant;

  # RCM boot of one kernel, initrd and cmdline, with the RCM overlay set
  # (mkRcmBootScript's arguments): baseRcm and rcmBundle per variant, one bootImg.
  # tegrarcm and tegrahost are the flashing host's tegrarcm_v2 and tegrahost_v2.
  mkRcm = { kernel, initrd, cmdline, additionalDtbOverlays, tegrarcm, tegrahost }: rec {
    # Each variant's scope with its RCM run as the reference, so bldtb,
    # cpublInput and dceInput are rebuilt against it.
    variants = lib.mapAttrs
      (_: v: v.overrideScope (final: prev: {
        # inputs are coldboot's (the T264 stmm), unused by RCM.
        reference = prev.reference.override { mode = "rcm"; inputs = [ ]; inherit additionalDtbOverlays; };
        rcmLeaves = leaves.rcm final v.dce-fw;
      }))
      self.variants;
    baseRcm = lib.mapAttrs (_: v: v.reference) variants;
    # The board name and base cmdline come from the board conf, the same for every variant.
    bootImg = self.callPackage ./boot-img.nix {
      inherit kernel initrd cmdline;
      baseRcm = variants.${(builtins.head self.variantsList).key}.reference;
    };
    rcmBundle = lib.mapAttrs
      (_: v: v.callPackage ./rcm-bundle.nix { inherit bootImg tegrarcm tegrahost; baseRcm = v.reference; leaves = v.rcmLeaves; })
      variants;
  };

  # Assembly can change the BUP without changing its base images or leaves.
  # Hash its source here, not the BUP output, which depends on UEFI.
  versionHash = builtins.hashString "sha256"
    (toString (map (v: v.reference) (lib.attrValues self.variants) ++ lib.attrValues self.common ++ map (v: v.dce-fw) (lib.attrValues self.variants))
      + toString (map (file: builtins.hashFile "sha256" file) [
      ./default.nix
      ./signed-firmware.nix
      ./signed-firmware.sh
      ./bup-payload.nix
    ]));
})
