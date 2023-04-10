# TODO: Should try to merge with upstream nixpkgs's open.nix nvidia driver
{ stdenv
, lib
, fetchgit
, kernel
}:

stdenv.mkDerivation rec {
  pname = "nvidia-display-driver";
  version = "jetson_35.2.1";

  src = fetchgit {
    url = "https://nv-tegra.nvidia.com/tegra/kernel-src/nv-kernel-display-driver.git";
    rev = "5f54f1d5a58966fc5c84d41360aefbde466f7777";
    sha256 = "sha256-ZY3eaP6dko6GnagcJIwAEb+aZ+IYxA+SsiaYBGK42oA=";
  };

  sourceRoot = "nv-kernel-display-driver-5f54f1d/NVIDIA-kernel-module-source-TempVersion";

  patches = [
    # This is needed because of nixos-unstable change from GCC 9 to 12. This
    # change has been backported from jetson_35.3.1, and because of that,
    # it should also be removed when moving to jetson_35.3.1
    ./add-mno-outline-atomics-for-aarch64.patch
  ];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernel.makeFlags ++ [
    "SYSSRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/source"
    "SYSOUT=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "MODLIB=$(out)/lib/modules/${kernel.modDirVersion}"
  ] ++ lib.optionals ((stdenv.buildPlatform != stdenv.hostPlatform) && stdenv.hostPlatform.isAarch64) [
    "TARGET_ARCH=aarch64"
  ];

  # Avoid an error in modpost: "__stack_chk_guard" [.../nvidia.ko] undefined
  NIX_CFLAGS_COMPILE = "-fno-stack-protector";

  installTargets = [ "modules_install" ];
  enableParallelBuilding = true;

  passthru.meta = {
    license = with lib.licenses; [ mit /* OR */ gpl2Only ];
  };
}
