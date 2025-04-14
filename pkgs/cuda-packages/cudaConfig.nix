_: {
  # Only Jetson devices are supported.
  hostRedistSystem = "linux-aarch64";
  data = {
    # GPU entries come from
    # https://github.com/NixOS/nixpkgs/blob/f680a9ecd4fa48fc00d3a3cd6babb44cc48a4408/pkgs/development/cuda-modules/gpus.nix
    gpus = {
      "7.2" = {
        # Jetson AGX Xavier, Drive AGX Pegasus, Xavier NX
        archName = "Volta";
        cudaCapability = "7.2";
        isJetson = true;
        minCudaMajorMinorVersion = "10.0";
        dontDefaultAfterCudaMajorMinorVersion = null;
        # Note: without `cuda_compat`, maxCudaMajorMinorVersion is 11.8
        # https://docs.nvidia.com/cuda/cuda-for-tegra-appnote/index.html#deployment-considerations-for-cuda-upgrade-package
        maxCudaMajorMinorVersion = "12.2";
      };
      "8.7" = {
        # Jetson AGX Orin and Drive AGX Orin only
        archName = "Ampere";
        cudaCapability = "8.7";
        isJetson = true;
        minCudaMajorMinorVersion = "11.4";
        dontDefaultAfterCudaMajorMinorVersion = null;
        maxCudaMajorMinorVersion = "12.2";
      };
    };
    # NVCC compatibilities come from
    # https://github.com/NixOS/nixpkgs/blob/f680a9ecd4fa48fc00d3a3cd6babb44cc48a4408/pkgs/development/cuda-modules/nvcc-compatibilities.nix
    nvccCompatibilities = {
      # Added support for Clang 12 and GCC 11
      # https://docs.nvidia.com/cuda/archive/11.4.4/cuda-toolkit-release-notes/index.html#cuda-general-new-features
      "11.4" = {
        clang = {
          maxMajorVersion = "12";
          minMajorVersion = "7";
        };
        gcc = {
          # NOTE: There is a bug in the version of GLIBC that GCC 11 uses which causes it to fail to compile some CUDA
          # code. As such, we skip it for this release, and do the bump in 11.6 (skipping 11.5).
          # https://forums.developer.nvidia.com/t/cuda-11-5-samples-throw-multiple-error-attribute-malloc-does-not-take-arguments/192750/15
          # maxMajorVersion = "11";
          maxMajorVersion = "10";
          minMajorVersion = "6";
        };
      };
    };
  };
}
