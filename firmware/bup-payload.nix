# bup: `flash.sh --bup --multi-spec`, i.e. l4t_bup_gen run once per variant over
# signedFirmware. $out has payloads_<socFamily>/*.
{ lib, runCommand, buildPackages, cfg, jetpack, signedFirmware, variantsList }:
let
  flash-tools = jetpack.l4tFlashTools;
in
runCommand "bup-${cfg.name}-${jetpack.l4tMajorMinorPatchVersion}" { } (''
  set -euo pipefail
  mkdir stage
  cd stage
  ln -s ${flash-tools}/bootloader/BUP_generator.py .

  # $1 signedFirmware dir, $2 spec, $3 fuselevel, $4 baseColdboot
  variant() {
    rm -rf signed
    mkdir signed
    # Writable: l4t_bup_gen copies these over each other across variants.
    cp -L --no-preserve=mode $1/* ${lib.optionalString (jetpack.socType == "t234") "$4/br_bct_b_BR.bct"} signed/
    # Unsigned rows (VER) are read from bootloader/ itself.
    for f in signed/*; do ln -sfn "$f" .; done
    # A fresh shell, as in flash.sh: stdenv's options (nullglob) break it.
    LDK_DIR=${flash-tools} support_multi_spec=1 clean_up=0 single_bup_blob=0 bup_type= \
      ${lib.getExe buildPackages.bash} -c 'source "$0"; l4t_bup_gen "$@"' ${flash-tools}/bootloader/l4t_bup_gen.func \
      "" "$2" "$3" generic "" "" ${jetpack.chipId}
  }
'' + lib.concatMapStrings
  (v: ''
    variant ${signedFirmware}/${v.key} ${v.spec} ${v.fuselevel} ${v.reference}
  '')
  variantsList + ''
  mkdir $out
  cp payloads_*/* $out/
'')
