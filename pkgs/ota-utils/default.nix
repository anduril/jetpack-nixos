{ lib, stdenvNoCC, util-linux, e2fsprogs, tegra-eeprom-tool, l4tVersion }:

stdenvNoCC.mkDerivation {
  name = "ota-utils";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin $out/share
    cp ${./ota-setup-efivars.sh} $out/bin/ota-setup-efivars
    cp ${./ota-apply-capsule-update.sh} $out/bin/ota-apply-capsule-update
    cp ${./ota-check-firmware.sh} $out/bin/ota-check-firmware
    cp ${./ota_helpers.func} $out/share/ota_helpers.func
    chmod +x $out/bin/ota-setup-efivars $out/bin/ota-apply-capsule-update $out/bin/ota-check-firmware

    for fname in ota-setup-efivars ota-apply-capsule-update; do
      substituteInPlace $out/bin/$fname \
        --replace "@ota_helpers@" "$out/share/ota_helpers.func"
      sed -i '2a export PATH=${lib.makeBinPath [ util-linux e2fsprogs tegra-eeprom-tool ]}:$PATH' $out/bin/$fname
    done

    substituteInPlace $out/bin/ota-check-firmware \
      --replace "@l4tVersion@" "${l4tVersion}"

    patchShebangs $out/bin/*
  '';
}
