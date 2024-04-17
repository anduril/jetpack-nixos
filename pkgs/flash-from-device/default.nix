{ lib, pkgsStatic, runCommand, tegra-eeprom-tool-static }:

let
  # Make the package smaller so it doesn't blow up the initrd size
  staticDeps = runCommand "static-deps" { } ''
    mkdir -p $out/bin
    cp ${pkgsStatic.mtdutils}/bin/mtd_debug $out/bin
    cp ${pkgsStatic.mtdutils}/bin/flash_erase $out/bin
    cp ${tegra-eeprom-tool-static}/bin/tegra-boardspec $out/bin
  '';
  name = "flash-from-device";
in
runCommand name { meta.mainProgram = name; } ''
  mkdir -p $out/bin

  cat > $out/bin/flash-from-device <<EOF
  #!${pkgsStatic.busybox}/bin/sh
  export PATH="${lib.makeBinPath [ pkgsStatic.busybox staticDeps ]}:$PATH"
  EOF
  cat ${./flash-from-device.sh} >> $out/bin/flash-from-device
  substituteInPlace $out/bin/flash-from-device \
    --replace "@ota_helpers_func@" "${../ota-utils/ota_helpers.func}"
  chmod +x $out/bin/flash-from-device
''
