# TODO: Should try to merge with upstream nixpkgs's open.nix nvidia driver
{ stdenv
, lib
, kernel
, gitRepos
, l4tMajorMinorPatchVersion
}:

stdenv.mkDerivation {
  pname = "nvidia-display-driver";
  version = "jetson_${l4tMajorMinorPatchVersion}";
  __structuredAttrs = true;
  strictDeps = true;

  src = gitRepos."tegra/kernel-src/nv-kernel-display-driver";

  setSourceRoot = "sourceRoot=$(echo */nvdisplay)";

  patches = [ ./display-driver-reproducibility-fix.patch ./0001-conftest-Add-Wno-implicit-function-declaration-and-W.patch ];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernel.commonMakeFlags ++ [
    "SYSSRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/source"
    "SYSOUT=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "MODLIB=$(out)/lib/modules/${kernel.modDirVersion}"
  ] ++ lib.optionals ((stdenv.buildPlatform != stdenv.hostPlatform) && stdenv.hostPlatform.isAarch64) [
    "TARGET_ARCH=aarch64"
  ];

  installTargets = [ "modules_install" ];
  enableParallelBuilding = true;

  passthru.meta = {
    license = with lib.licenses; [ mit /* OR */ gpl2Only ];
  };
}
