{ gitRepos
, l4tVersion
, opteeStdenv
, socType
}:

opteeStdenv.mkDerivation {
  pname = "arm-trusted-firmware";
  version = l4tVersion;
  src = gitRepos."tegra/optee-src/atf";
  makeFlags = [
    "-C arm-trusted-firmware"
    "BUILD_BASE=$(PWD)/build"
    "CROSS_COMPILE=${opteeStdenv.cc.targetPrefix}"
    "DEBUG=0"
    "LOG_LEVEL=20"
    "PLAT=tegra"
    "SPD=opteed"
    "TARGET_SOC=${socType}"
    "V=0"
    # binutils 2.39 regression
    # `warning: /build/source/build/rk3399/release/bl31/bl31.elf has a LOAD segment with RWX permissions`
    # See also: https://developer.trustedfirmware.org/T996
    "LDFLAGS=-no-warn-rwx-segments"
  ];

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp ./build/tegra/${socType}/release/bl31.bin $out/bl31.bin

    runHook postInstall
  '';

  meta.platforms = [ "aarch64-linux" ];
}
