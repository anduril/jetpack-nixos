# A scope: a member overridden with overrideScope (e.g. a variant's, through
# `variants`) reaches signedFirmware and bup.
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
