{ lib, stdenvNoCC, bash, util-linux, e2fsprogs, tegra-eeprom-tool, efiSysMountPoint ? "/boot", expectedBiosVersion ? "Unknown" }:

stdenvNoCC.mkDerivation {
  name = "ota-utils";

  depsBuildHost = [ bash ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  env = { inherit efiSysMountPoint expectedBiosVersion; };

  buildInputs = [ bash ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share
    cp ${./ota-setup-efivars.sh} $out/bin/ota-setup-efivars
    cp ${./ota-apply-capsule-update.sh} $out/bin/ota-apply-capsule-update
    cp ${./ota-check-firmware.sh} $out/bin/ota-check-firmware
    cp ${./ota-abort-capsule-update.sh} $out/bin/ota-abort-capsule-update
    cp ${./ota_helpers.sh} $out/share/ota_helpers.sh
    chmod +x $out/bin/ota-setup-efivars $out/bin/ota-apply-capsule-update $out/bin/ota-check-firmware $out/bin/ota-abort-capsule-update

    substituteInPlace "$out/share/ota_helpers.sh" \
      --subst-var efiSysMountPoint

    for fname in ota-setup-efivars ota-apply-capsule-update ota-abort-capsule-update ota-check-firmware; do
      substituteInPlace $out/bin/$fname \
        --subst-var expectedBiosVersion \
        --subst-var efiSysMountPoint \
        --replace "@ota_helpers@" "$out/share/ota_helpers.sh"
      sed -i '2a export PATH=${lib.makeBinPath [ util-linux e2fsprogs tegra-eeprom-tool ]}:$PATH' $out/bin/$fname
    done

    patchShebangs --host $out/bin

    runHook postInstall
  '';
}
