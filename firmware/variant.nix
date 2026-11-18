# variants.<key>: the scope of one firmware.variants entry. Its leaves are
# signed against `reference`, the variant's stock flash.sh run (baseColdboot):
# its layout, ratchet blob and overlay set. Override `reference`, `bldtb` or
# an input and everything built from it, through bup, follows.
{ lib, pkgs, cfg, jetpack, dtbsDir, sign, boardSpec, variantKey, variants }:
variant: self:
let
  inherit (jetpack) l4tMajorMinorPatchVersion uefi-firmware socFamily l4tAtLeast;
  cpublName = (if l4tAtLeast "38" then "uefi_${socFamily}_general" else "uefi_jetson") + "_with_dtb.bin";
in
{
  inherit variant;
  inherit (variant) fuselevel;
  key = variantKey variant;
  # flash.sh's BUP spec (generate_specs), with the board name the device
  # matches against (ota-setup-efivars).
  spec = boardSpec variant (if variant.chiprev == "" then "0" else variant.chiprev) cfg.flashScriptOverrides.targetBoard;

  reference = self.callPackage ./base-flash-bins.nix {
    inputs = lib.optional (jetpack.socType == "t264") "standalonemm_jetson.pkg";
  };
  # The first variant with this fuselevel: l4t_bup_gen's common images come from it.
  commonOpMode = variants.${variantKey (lib.findFirst (w: w.fuselevel == variant.fuselevel) variant cfg.firmware.variants)}.reference;

  bldtb = jetpack.bldtb {
    inherit pkgs;
    flash-tools = jetpack.l4tFlashTools;
    name = "${cfg.name}-bldtb-${l4tMajorMinorPatchVersion}";
    dtb = dtbsDir;
    overlaySet = "${self.reference}/overlaySet";
  };

  # concatenate_cpubl_bldtb / concatenate_dcebin_kerneldtb: plain appends.
  cpublInput = pkgs.runCommand "${cfg.name}-cpubl-input-${l4tMajorMinorPatchVersion}" { } ''
    mkdir $out
    cat ${uefi-firmware}/uefi_jetson.bin ${self.bldtb}/* > $out/${cpublName}
  '';
  dceInput = pkgs.runCommand "${cfg.name}-dce-input-${l4tMajorMinorPatchVersion}" { } ''
    mkdir $out
    if [ "$(cat ${self.reference}/dce/base)" = bldtb ]; then base=(${self.bldtb}/*); else base=${dtbsDir}/$(cat ${self.reference}/overlaySet/dtb); fi
    # concatenate_dcebin_kerneldtb: --dce_overlay_dtb is fdtoverlay'd onto the base first.
    overlays=()
    IFS=, read -ra names < ${self.reference}/dce/overlay-order || : # no trailing newline
    for f in "''${names[@]}"; do
      case $f in /*) overlays+=("$f");; *) overlays+=(${self.reference}/dce/overlays/"$f");; esac
    done
    if [ ''${#overlays[@]} -gt 0 ]; then
      PATH=${lib.makeBinPath jetpack.l4tFlashTools.flashDeps}:$PATH fdtoverlay -i "$base" -o dce-base.dtb "''${overlays[@]}"
      base=dce-base.dtb
    fi
    cat ${self.reference}/dce/*.bin "$base" > "$out/$(cat ${self.reference}/dce/name)"
  '';

  # Signed per variant: the bootloader DTB carries the variant's overlaySet.
  cpu-bootloader = sign self.reference "cpubl" "A_cpu-bootloader" { image = self.cpublInput; };
  dce-fw = sign self.reference "dce" "A_dce-fw" { image = self.dceInput; };
  leaves = { inherit (self) cpu-bootloader dce-fw; };
}
