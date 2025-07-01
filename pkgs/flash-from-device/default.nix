{ lib, pkgsStatic, runCommand, tegra-eeprom-tool-static }:

let
  mtdutils = pkgsStatic.mtdutils.overrideAttrs (_: {
    # Grab patches merged after 2.3.0 to let mtdutils build with musl
    # https://lists.openembedded.org/g/openembedded-core/topic/patch_mtd_utils_upgrade_to/111205949
    src = fetchGit {
      url = "git://git.infradead.org/mtd-utils.git";
      rev = "77981a2888c711268b0e7f32af6af159c2288e23";
    };
    version = "2.3.0-unstable-2025-06-02";

    # Workaround build failure with pkgsStatic.mtdutils in NixOS 24.11
    # > configure: WARNING: cannot find CMocka library required for unit tests
    # > configure: unit tests can optionally be disabled
    # > configure: error: missing one or more dependencies
    configureFlags = [ ];
    doCheck = false;
  });

  # Make the package smaller so it doesn't blow up the initrd size
  staticDeps = runCommand "static-deps" { } ''
    mkdir -p $out/bin
    cp ${mtdutils}/bin/mtd_debug $out/bin
    cp ${mtdutils}/bin/flash_erase $out/bin
    cp ${tegra-eeprom-tool-static}/bin/tegra-boardspec $out/bin
  '';
  name = "flash-from-device";
in
runCommand name { meta.mainProgram = name; } ''
  mkdir -p $out/bin

  cat > $out/bin/flash-from-device <<EOF
  #!${pkgsStatic.busybox}/bin/sh
  export PATH="${lib.makeBinPath [ pkgsStatic.busybox staticDeps ]}"
  EOF
  cat ${./flash-from-device.sh} >> $out/bin/flash-from-device
  substituteInPlace $out/bin/flash-from-device \
    --replace "@ota_helpers_func@" "${../ota-utils/ota_helpers.func}"
  chmod +x $out/bin/flash-from-device
''
