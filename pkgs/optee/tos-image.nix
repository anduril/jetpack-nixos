{ gitRepos
, lib
, runCommand
, python3
, dtc
, bspSrc
, armTrustedFirmware
, opteeOS
, nukeReferences
, socType
}:


let
  flavor = lib.replaceStrings [ "t" ] [ "" ] socType;
  nvopteeSrc = gitRepos."tegra/optee-src/nv-optee";

in
runCommand "tos.img"
{
  nativeBuildInputs = [ dtc python3 nukeReferences ];
} ''
  dtc -I dts -O dtb -o optee.dtb ${nvopteeSrc}/optee/tegra${flavor}-optee.dts

  python3 ${bspSrc}/nv_tegra/tos-scripts/gen_tos_part_img.py \
    --monitor ${armTrustedFirmware}/bl31.bin \
    --os ${opteeOS}/core/tee-raw.bin \
    --dtb optee.dtb \
    --tostype optee \
    $out
''
