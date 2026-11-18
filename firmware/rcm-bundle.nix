# rcmBundle@variant: bootloader/rcmboot_blob as `flash.sh --no-flash --rcm-boot`
# leaves it, except blob.bin. blob/ is baseRcm's blob.xml and files with our
# images swapped in as symlinks; the flashing host runs tegrahost --generateblob
# over it. Also baseRcm's rcmbootcmd.txt and the files it downloads. Relocatable.
{ lib, runCommand, cfg, jetpack, key, baseRcm, leaves, bootImg, dtbsDir, tegrarcm, tegrahost }:
let
  flash-tools = jetpack.l4tFlashTools;
in
runCommand "rcm-bundle-${cfg.name}-${key}${jetpack.l4tMajorMinorPatchVersion}" { } (''
  set -euo pipefail
  export PATH=${lib.makeBinPath flash-tools.flashDeps}:$PATH
  mkdir blob
  cd blob
  cp ${baseRcm}/blob/* .
  chmod u+w *
  # Replaces baseRcm's file for one blob.xml entry with ours, in place, under
  # the name blob.xml already gives it (so blob.xml stays stock's).
  #   $1  the entry's `type` attribute in blob.xml (e.g. kernel, bootloader)
  #   $2  our file for it
  #   $3  how to place it: "ln -s" shares the store path between variants; "cp"
  #       for a file inside a bigger output (the kernel DTB), where a link would
  #       drag that whole directory into the closure
  ours() {
    local n
    n=$(xmlstarlet sel -t -v "//file[@type='$1']/@name" blob.xml)
    test -n "$n"
    $3 -f "$2" "$n"
  }
  ours kernel ${bootImg}/boot.img "ln -s"
  ${lib.optionalString (jetpack.socType == "t234") "ours kernel_dtb ${dtbsDir}/$(cat ${baseRcm}/overlaySet/dtb) cp"}
'' + lib.concatStrings (lib.mapAttrsToList (type: leaf: "ours ${type} ${leaf}/* \"ln -s\"\n") leaves) + ''
  # Smoke test of what the host runs.
  ${flash-tools}/bootloader/tegrahost_v2 --chip ${jetpack.chipId} 0 --generateblob blob.xml $TMPDIR/blob.bin
  cd ..
  mkdir $out
  cp -a blob $out/
  cp ${baseRcm}/rcm/* $out/
  install -m 755 ${tegrarcm} $out/tegrarcm_v2
  install -m 755 ${tegrahost} $out/tegrahost_v2
'')
