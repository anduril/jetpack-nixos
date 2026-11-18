# signedFirmware@variant: $out/<variant key>/{flash.idx, files}, as `flash.sh
# --sign` leaves them. Each row links to our leaf for that partition, else to
# variant0's baseColdboot image in $out/.common if l4t_bup_gen's table marks it
# common to all boards, else to a copy of the variant's own; size and sha1 are
# rewritten and VER is restamped with the BSP build date.
{ lib, runCommand, cfg, jetpack, defaultColdboot, common, variantsList }:
let
  flash-tools = jetpack.l4tFlashTools;
in
runCommand "signed-${cfg.name}-${jetpack.l4tMajorMinorPatchVersion}" { } (''
  socFamily=${jetpack.socFamily}
  bupGen=${flash-tools}/bootloader/l4t_bup_gen.func
  release=${jetpack.bspSrc}/nv_tegra/nv_tegra_release
  source ${./signed-firmware.sh}
'' + lib.concatMapStrings
  (v: ''
    variant ${v.key} ${v.reference} ${defaultColdboot} ${v.commonOpMode} ${lib.escapeShellArgs (lib.mapAttrsToList (partition: leaf: "${partition}=${leaf}") (common // v.leaves))}
  '')
  variantsList)
