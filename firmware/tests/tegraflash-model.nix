# How `flash.sh --no-flash --sign|--rcm-boot` calls tegraflash.py, for
# tegraflash-audit.py to hold the recorded calls to. Under --no-flash,
# odmsign.func runs every tegraflash process: the sign pass (odmsign_ext_sign)
# and, for RCM, `rcmboot --no_flash` (odmsign_gen_rcmboot_blob). Each flag
# tegraflash may see is listed with its allowed counts (`n`); any other flag
# fails the build. `value` pins what Nix decides, `path` and `activeKeyOf`
# pin key files (compared as resolved paths); other values are flash.sh's
# board config and stay free.
# `signing` is pkgs/l4t-sign/flash-args.nix on the flashArgs and keys signImage
# gets, so a mismatch also means per-image signing reads the options wrong.
{ lib, jetpack, variant, signing }:
let
  inherit (jetpack) chipId;
  inherit (signing) r39 t264 pkcFile sbkFile flags passthrough;

  any = { n = [ 1 ]; };
  maybe = { n = [ 0 1 ]; };
  is = value: { n = [ 1 ]; inherit value; };
  bool = n: { n = [ n ]; bool = true; };
  times = n: spec: spec // { n = [ n ]; };
  has = f: if lib.elem f flags then 1 else 0;
  passthroughCount = w: lib.count (x: x == w) passthrough;
  # As keyFlashArgs passes them to flash.sh.
  str = f: if f == null then null else "${f}";

  # odmsign_ext_sign appends --key/--encrypt_key; r39 FLASHARGS has them too
  # (flash.sh:6017-6026, its "T264 rcm-boot only" comment notwithstanding).
  keyCopies = if r39 then 2 else 1;
  keys = {
    "--key" = times (if pkcFile == null then 0 else keyCopies)
      (if t264 then { activeKeyOf = str pkcFile; } else { path = str pkcFile; });
    "--key_list" = times (if t264 && pkcFile != null then 1 else 0) { path = str pkcFile; };
    "--encrypt_key" = times (if sbkFile == null then 0 else keyCopies) { path = str sbkFile; };
    "--hsm" = bool (has "--hsm" + passthroughCount "--hsm");
    "--disable_random_iv" = bool
      ((if sbkFile != null then has "--disable-random-iv" else 0) + passthroughCount "--disable_random_iv");
    "--skipuid" = bool (passthroughCount "--skipuid");
  };

  # BCT inputs named by the board config (flash.sh BCTARGS, each behind its
  # conf variable). They only feed NVIDIA's own BCT build.
  bctInputs = lib.genAttrs [
    "--sdram_config"
    "--uphy_config"
    "--device_config"
    "--misc_config"
    "--misc_cold_boot_config"
    "--pinmux_config"
    "--gpioint_config"
    "--pmic_config"
    "--pmc_config"
    "--deviceprod_config"
    "--prod_config"
    "--scr_config"
    "--scr_cold_boot_config"
    "--wb0sdram_config"
    "--br_cmd_config"
    "--uphy"
    "--dev_params"
    "--mb2bct_cfg"
    "--coldboot_bct_cfg"
    "--rcmboot_bct_cfg"
    "--bct_flags_file"
    "--overlay_bct_flags_file"
  ]
    (_: maybe);

  sign = bctInputs // keys // {
    "--cmd" = is (if r39 then " sign" else "sign");
    "--chip" = is chipId;
    "--bl" = any;
    "--applet" = any;
    "--bldtb" = any;
    "--overlay_dtb" = any;
    "--dce_overlay_dtb" = maybe;
    # r36 passes it even when empty; r39 only when set (Thor's confs set none).
    "--odmdata" = if r39 then maybe else any;
    "--concat_cpubl_bldtb" = bool 1;
    "--cpubl" = any;
    "--cpubl_rcm" = if t264 then maybe else any;
    "--minratchet_config" = any;
    "--bins" = any;
    "--bct_backup" = bool ;
    "--boot_chain" = is "A";
    "--keep" = bool (1 + passthroughCount "--keep");
    # Board configs may set RAMCODE themselves; T264 flash.sh requires one.
    "--ramcode" = if variant.ramcode != null then is variant.ramcode else if t264 then any else maybe;
    ${if !t264 then "--cfg" else "--coldboot_pt_layout"} = any;
  } // lib.optionalAttrs r39 {
    "--rawkerneldtb" = any;
    "--no_pva" = is "0";
  };
in
{
  invocations = [{ role = "sign"; flags = sign; }];
}
