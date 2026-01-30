final: prev:
let
  inherit (final.stdenv.hostPlatform) system;
in
{
  nvidia-jetpack5 = import ./mk-overlay.nix
    {
      # Below 3 are from release notes
      jetpackMajorMinorPatchVersion = "5.1.5";
      l4tMajorMinorPatchVersion = "35.6.2";
      cudaMajorMinorPatchVersion = "11.4.298";

      # used to version libnvidia-ptxjitcompiler.so. L4T r35 uses l4tMajorMinorPatchVersion, so set to null
      # and we'll use l4tMajorMinorPatchVersion instead
      cudaDriverMajorMinorVersion = null;

      bspHash = "sha256-u+dRtBHhN+bxwiuGlZwEhSXrpSfSb+kuC50+FjobSTg=";
      bspPostPatch =
        let
          overlay_mb1bct = final.fetchzip {
            url = "https://developer.nvidia.com/downloads/embedded/L4T/r35_Release_v6.2/overlay_mb1bct_35.6.2.tbz2";
            sha256 = "sha256-4+oCK2rV6X5QEHJKAIXh3XC2Nc59LVQp5Ecgp8ZlWrM=";
          };
        in
        ''
          cp -r ${overlay_mb1bct}/* .
        '';
    }
    final
    prev;

  nvidia-jetpack6 = import ./mk-overlay.nix
    {
      # Below 3 are from release notes
      jetpackMajorMinorPatchVersion = "6.2.1";
      l4tMajorMinorPatchVersion = "36.4.4";
      cudaMajorMinorPatchVersion = "12.6.10";

      # nix build .#legacyPacakges.nvidia-l4t-3d-core.src; unpack the deb; find libnvidia-ptxjitcompiler.so
      # and use that.
      cudaDriverMajorMinorVersion = "540.4.0";

      bspHash = "sha256-ps4RwiEAqwl25BmVkYJBfIPWL0JyUBvIcU8uB24BDzs=";
      bspPostPatch =
        let
          overlay_mb1bct = final.fetchzip {
            url = "https://developer.nvidia.com/downloads/embedded/L4T/r36_Release_v4.4/overlay_mb1bct_36.4.4.tbz2";
            sha256 = "sha256-QWktb8/cZg9ch7IZ3GRnsLuhU9dD1rYrogBeQvWCg2E=";
          };
        in
        ''
          cp -r ${overlay_mb1bct}/* .
        '';
    }
    final
    prev;

  nvidia-jetpack7 = import ./mk-overlay.nix
    {
      jetpackMajorMinorPatchVersion = "7.0";
      l4tMajorMinorPatchVersion = "38.2.1";
      cudaMajorMinorPatchVersion = "13.0.2";

      cudaDriverMajorMinorVersion = "580.00";

      bspHash = "sha256-raHtaLeODpgHxw24e+ViturGqpXVOL9jtun4owCDcEs=";
      bspPatches = [ ./pkgs/r38-bsp.patch ];
    }
    final
    prev;

  # Due to the interplay between JetPack releases and supported CUDA versions, the choice of CUDA version drives the
  # version of nvidia-jetpack made the default to avoid the need to maintain tedious overlays and ensures the two stay
  # in sync by default.
  #
  # Thanks to the functionality added in https://github.com/NixOS/nixpkgs/pull/406568, we can build packages
  # using variants of Nixpkgs through the Flake CLI. See https://nixos.org/manual/nixpkgs/stable/#cuda-using-cudapackages-pkgs
  # for an example.
  #
  # Consider a user trying to build a hypothetical package foo which works with all versions of nvidia-jetpack. If
  # they build .#blarg (assuming proper configuration of Nixpkgs and use of our overlay), blarg receives
  # nvidia-jetpack5 as nvidia-jetpack and nvidia-jetpack5.cudaPackages (CUDA 11.4) as cudaPackages.
  # If they build .#cudaPackages_12.pkgs.blarg, blarg receives nvidia-jetpack6 as nvidia-jetpack and
  # nvidia-jetpack6.cudaPackages (CUDA 12.6) as cudaPackages. If the version of nvidia-jetpack did not depend on
  # the version of the CUDA package set, blarg would have received nvidia-jetpack5 as nvidia-jetpack (since it would
  # stay unchanged) and nvidia-jetpack6.cudaPackages (CUDA 12.6) as cudaPackages -- this is likely unintentional!
  nvidia-jetpack =
    # Support for pre-11.4 belongs with JetPack 4, which is no longer maintained.
    # CUDA 11.4 - 12.2 is supported either natively (11.4) or through cuda_compat (everything else).
    if final.cudaPackages.cudaOlder "12.3" then
      final.nvidia-jetpack5

    # CUDA 12.4 - 12.9 is supported either natively (12.4) or through cuda_compat (everything else).
    # NOTE: CUDA 12.3 isn't supported by JetPack 5 or 6, but we lump it in with JetPack 6 to avoid throwing.
    else if final.cudaPackages.cudaOlder "13.0" then
      final.nvidia-jetpack6

    # CUDA 13.0+ is supported by JetPack 7, which we don't yet package.
    else
      final.nvidia-jetpack7;

  # Set cudaPackage package sets to our JetPack-constructed package sets if we are on aarch64-linux. This is strictly
  # worse than conditioning on Jetson capabilities, but allows us to avoid infinite recursion when depending on the
  # version of the default CUDA package set. Since non-Jetson ARM platforms aren't supported by the CUDA 11.4 release,
  # there's no risk of mixing up Jetson and ARM binaries.
  # NOTE: We must use 11.4 because of runtime version-checks in some CUDA libraries (like cuDNN or TensorRT) which fail if
  # we use newer versions of libraries like cuBLAS, even with cuda_compat.
  cudaPackages_11_4 =
    prev.cudaPackages_11_4.override (prevArgs:
      if system == "aarch64-linux" then
        {
          # Replace manifests with a single entry containing just the release of CUDA.
          # NOTE: This value must match the value used in construction of nvidia-jetpack5.
          manifests.cuda.release_label = "11.4.298";
        }
      else
        {
          manifests = prevArgs.manifests // {
            # Use cuDNN 8.6 to more closely align with the versions JetPack 5 provides.
            # NOTE: TensorRT is provided for x86_64-linux by our cuda-packages-11-4-extension.nix overlay.
            cudnn = final._cuda.manifests.cudnn."8.6.0";
          };
        });

  # Use 11.4 as the default CUDA release (sorry ARM SBSA NVIDIA users).
  cudaPackages_11 = final.cudaPackages_11_4;

  # Override upstream's manifest selection so the version of TensorRT used is consistent
  # NOTE: This needs to stay up to date with:
  # https://github.com/NixOS/nixpkgs/blob/921f06852867d06373bb0fa7ec570d14275b436d/pkgs/top-level/cuda-packages.nix
  # https://github.com/nixos-cuda/cuda-legacy/blob/3323fa062d19f7a0b15fd720a94bc05ad8c664cb/overlays/cudaPackagesVersions.nix
  cudaPackages_12_6 = prev.cudaPackages_12_6.override (prevArgs: {
    manifests = prevArgs.manifests // {
      tensorrt = final._cuda.manifests.tensorrt."10.7.0";
    };
  });
  cudaPackages_12_8 = prev.cudaPackages_12_8.override (prevArgs: {
    manifests = prevArgs.manifests // {
      tensorrt = final._cuda.manifests.tensorrt."10.7.0";
    };
  });
  cudaPackages_12_9 = prev.cudaPackages_12_9.override (prevArgs: {
    manifests = prevArgs.manifests // {
      tensorrt = final._cuda.manifests.tensorrt."10.7.0";
    };
  });
  cudaPackages_13_0 = prev.cudaPackages_13_0.override (prevArgs: {
    manifests = prevArgs.manifests // {
      # Orin isn't supported on JetPack 7 at the moment so use the newest version available.
      tensorrt = final._cuda.manifests.tensorrt."10.14.1";
    };
  });

  cudaPackages = final.cudaPackages_11;

  _cuda = prev._cuda.extend (_: prevCuda: {
    extensions = prevCuda.extensions ++ [
      # General extensions
      (import ./pkgs/cuda-extensions { inherit (final) lib; })

      # Version-specific extensions.
      # As a quirk of the way the CUDA package sets are instantiated, using `overrideScope` is only effective on the
      # top-level attributes of the CUDA package set.
      # As an example, if we add the `debs` attribute, `cudaPackages.debs` will exist as expected. However,
      # `cudaPackages.pkgs.cudaPackages.debs` will not -- the extension provided to `overrideScope` is not threaded
      # through!
      # For now, we just conditionally apply extensions.
      # Replace CUDA packages from manifests with our own, which are built from debian installers, if we're using
      # CUDA 11.4.
      (import ./cuda-packages-11-4-extension.nix { inherit (final) lib; inherit system; })
    ];
  });
}
