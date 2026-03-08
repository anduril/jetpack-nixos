{ stdenv
, l4tMajorMinorPatchVersion
, gitRepos
, lib
, l4tAtLeast
, openssl
, dtc
, buildPackages
, pkg-config
}:
stdenv.mkDerivation (finalAttrs:
let
  socSpecialization = gitRepos ? "tegra/optee-src/atf_${finalAttrs.socType}";
  src = if socSpecialization then gitRepos."tegra/optee-src/atf_${finalAttrs.socType}" else gitRepos."tegra/optee-src/atf";
  srcDir = if socSpecialization then "arm-trusted-firmware.${finalAttrs.socType}" else "arm-trusted-firmware";

  l4tMajorVersion = lib.versions.major l4tMajorMinorPatchVersion;
in
{
  pname = "arm-trusted-firmware";
  version = l4tMajorMinorPatchVersion;

  inherit src;

  socType =
    if l4tMajorVersion == "35" then "t194"
    else if l4tMajorVersion == "36" then "t234"
    else if l4tMajorVersion == "38" then "t264"
    else throw "Unknown SoC type";

  # openssl is used to build fiptool
  buildInputs = lib.optionals (l4tAtLeast "38") [ openssl ];
  nativeBuildInputs = lib.optionals (l4tAtLeast "38") [ dtc openssl buildPackages.stdenv.cc pkg-config ];

  strictDeps = true;
  enableParallelBuilding = true;

  makeFlags = [
    "-C ${srcDir}"
    "BUILD_BASE=$(PWD)/build"
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
    "DEBUG=0"
    "LOG_LEVEL=20"
    "PLAT=tegra"
    "TARGET_SOC=${finalAttrs.socType}"
    "V=0"
    # binutils 2.39 regression
    # `warning: /build/source/build/rk3399/release/bl31/bl31.elf has a LOAD segment with RWX permissions`
    # See also: https://developer.trustedfirmware.org/T996
    "LDFLAGS=-no-warn-rwx-segments"
    "OPENSSL_DIR=${lib.getLib buildPackages.openssl}"
  ] ++ lib.optionals (finalAttrs.socType == "t194" || finalAttrs.socType == "t234") [
    "SPD=opteed"
  ] ++ lib.optionals (finalAttrs.socType == "t264") [
    "ARM_ARCH_MINOR=6"
    "CTX_INCLUDE_EL2_REGS=1"
    "SPD=spmd"
    "SP_LAYOUT_FILE=${src}/${srcDir}/secure_partition/sp_layout.json"
  ] ++ lib.optionals ((lib.versions.major l4tMajorMinorPatchVersion) == "36" && finalAttrs.socType != "t194") [
    "BRANCH_PROTECTION=3"
    "ARM_ARCH_MINOR=3"
  ];

  buildFlags = [ "all" ] ++ lib.optional (l4tAtLeast "38") "fiptool";

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp ./build/tegra/${finalAttrs.socType}/release/bl31.bin $out/bl31.bin

    ${lib.optionalString socSpecialization ''
      # From public sources, see instructions in nvidia-jetson-optee-source.tbz2
      dtc -I dts -O dtb -o nvidia-${finalAttrs.socType}.dtb ${srcDir}/fdts/nvidia-${finalAttrs.socType}.dts
      ${srcDir}/tools/fiptool/fiptool create --soc-fw $out/bl31.bin --soc-fw-config nvidia-${finalAttrs.socType}.dtb $out/bl31.fip
    ''}


    runHook postInstall
  '';

  meta.platforms = [ "aarch64-linux" ];
})
