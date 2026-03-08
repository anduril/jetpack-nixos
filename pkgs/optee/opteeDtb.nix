{ lib
, runCommand
, dtc
, optee-os
}:
let
  flavor = lib.replaceStrings [ "t" ] [ "" ] optee-os.socType;
in
runCommand "tegra-${flavor}-optee.dtb"
{
  nativeBuildInputs = [ dtc ];
} ''
  mkdir -p $out
  dtc -I dts -O dtb -o $out/tegra${flavor}-optee.dtb ${optee-os.src}/optee/tegra${flavor}-optee.dts
''
