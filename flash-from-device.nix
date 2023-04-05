{ pkgsAarch64, lib, writeScriptBin, runCommand, tegra-eeprom-tool-static }:

let
  # Make the package smaller so it doesn't blow up the initrd size
  staticDeps = runCommand "static-deps" {} ''
    mkdir -p $out/bin
    cp ${pkgsAarch64.pkgsStatic.mtdutils}/bin/mtd_debug $out/bin
    cp ${pkgsAarch64.pkgsStatic.mtdutils}/bin/flash_erase $out/bin
    cp ${tegra-eeprom-tool-static}/bin/tegra-boardspec $out/bin
  '';
in
writeScriptBin "flash-from-device" (''
  #!${pkgsAarch64.pkgsStatic.busybox}/bin/sh
  export PATH="${lib.makeBinPath [ pkgsAarch64.pkgsStatic.busybox staticDeps ]}:$PATH"
'' + (builtins.readFile ./flash-from-device.sh))
