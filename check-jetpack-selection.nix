{ lib, nixpkgs, overlay, pkgs, system }:
(
  let
    inherit (lib) assertMsg getAttrFromPath showAttrPath;
    inherit (lib.versions) major;

    mkPkgs = overlay': (import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        cudaCapabilities = [ "7.2" "8.7" ];
        cudaSupport = true;
      };
      overlays = [ overlay overlay' ];
    });

    variants = {
      pkgsCudaDefault = mkPkgs (_: _: { });

      pkgsCuda11 = mkPkgs (final: _: {
        cudaPackages = final.cudaPackages_11;
      });

      pkgsCuda12 = mkPkgs (final: _: {
        cudaPackages = final.cudaPackages_12;
      });
    };

    mkAsserts =
      { pkgsPath
        # ^ Path to the root of the attribute set to use as `pkgs`, through `variants`.
        #   For example, `["variants" "pkgsCuda11" "cudaPackages_12" "pkgs"]` would use
        #   `variants.pkgsCuda11.cudaPackages_12.pkgs` as the root package set.
      , expectedX86CudaMajorMinorVersion
      , expectedAarch64CudaMajorMinorVersion
      , expectedJetPackMajorVersion
      , expectedJetPackCudaMajorMinorVersion
      ,
      }:
      let
        prefix = showAttrPath pkgsPath;
        inherit (getAttrFromPath pkgsPath variants) cudaPackages nvidia-jetpack;
        actualCudaMajorMinorVersion = cudaPackages.cudaMajorMinorVersion;
        actualJetPackMajorVersion = major nvidia-jetpack.jetpackMajorMinorPatchVersion;
        actualJetPackCudaCudaMajorMinorVersion = nvidia-jetpack.cudaPackages.cudaMajorMinorVersion;
      in
      assert assertMsg (system == "x86_64-linux" -> actualCudaMajorMinorVersion == expectedX86CudaMajorMinorVersion)
        "${prefix}: Expected CUDA ${expectedX86CudaMajorMinorVersion} to be the default for x86_64-linux, not CUDA ${actualCudaMajorMinorVersion}";

      assert assertMsg (system == "aarch64-linux" -> actualCudaMajorMinorVersion == expectedAarch64CudaMajorMinorVersion)
        "${prefix}: Expected CUDA ${expectedAarch64CudaMajorMinorVersion} to be the default for aarch64-linux, not CUDA ${actualCudaMajorMinorVersion}";

      assert assertMsg (actualJetPackMajorVersion == expectedJetPackMajorVersion)
        "${prefix}: Expected JetPack ${expectedJetPackMajorVersion} to be the default, not JetPack ${actualJetPackMajorVersion}";

      assert assertMsg (actualJetPackCudaCudaMajorMinorVersion == expectedJetPackCudaMajorMinorVersion)
        (
          "${prefix}: Expected JetPack CUDA ${expectedJetPackCudaMajorMinorVersion} to be the default,"
          + " not JetPack CUDA ${actualJetPackCudaCudaMajorMinorVersion}"
        );

      # On aarch64-linux, the global CUDA package set should be *our* CUDA package set
      assert assertMsg (system == "aarch64-linux" -> expectedJetPackCudaMajorMinorVersion == actualCudaMajorMinorVersion)
        "${prefix}: Expected JetPack CUDA ${expectedJetPackCudaMajorMinorVersion} to be the default CUDA for aarch64-linux, not CUDA ${actualCudaMajorMinorVersion}";

      # We have to return something so give the empty attribute set.
      { };

    cuda11AsDefault = {
      expectedX86CudaMajorMinorVersion = "11.8";
      expectedAarch64CudaMajorMinorVersion = "11.4";
      expectedJetPackMajorVersion = "5";
      expectedJetPackCudaMajorMinorVersion = "11.4";
    };

    jetPack5AsDefault = cuda11AsDefault // {
      # nvidia-jetpack5.cudaPackages is the global default
      expectedX86CudaMajorMinorVersion = "11.4";
    };

    cuda12AsDefault = {
      expectedX86CudaMajorMinorVersion = "12.8";
      expectedAarch64CudaMajorMinorVersion = "12.6";
      expectedJetPackMajorVersion = "6";
      expectedJetPackCudaMajorMinorVersion = "12.6";
    };

    jetPack6AsDefault = cuda12AsDefault // {
      # nvidia-jetpack6.cudaPackages is the global default
      expectedX86CudaMajorMinorVersion = "12.6";
    };
  in
  pkgs.emptyFile # -- Dummy derivation

  # Assertions to verify properties we want hold true.

  # Cases CUDA 11 where everything is unchanged from the default
  // mkAsserts ({ pkgsPath = [ "pkgsCudaDefault" ]; } // cuda11AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCudaDefault" "cudaPackages_11" "pkgs" ]; } // cuda11AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCuda11" ]; } // cuda11AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCuda11" "cudaPackages_11" "pkgs" ]; } // cuda11AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCuda12" "cudaPackages_11" "pkgs" ]; } // cuda11AsDefault)

  ## Cases CUDA 11 where cudaPackages from nvidia-jetpack5 is made the global default
  // mkAsserts ({ pkgsPath = [ "pkgsCudaDefault" "nvidia-jetpack" "cudaPackages" "pkgs" ]; } // jetPack5AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCudaDefault" "nvidia-jetpack5" "cudaPackages" "pkgs" ]; } // jetPack5AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCuda11" "nvidia-jetpack" "cudaPackages" "pkgs" ]; } // jetPack5AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCuda11" "nvidia-jetpack5" "cudaPackages" "pkgs" ]; } // jetPack5AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCuda12" "nvidia-jetpack5" "cudaPackages" "pkgs" ]; } // jetPack5AsDefault)

  # Cases CUDA 12
  // mkAsserts ({ pkgsPath = [ "pkgsCudaDefault" "cudaPackages_12" "pkgs" ]; } // cuda12AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCuda11" "cudaPackages_12" "pkgs" ]; } // cuda12AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCuda12" ]; } // cuda12AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCuda12" "cudaPackages_12" "pkgs" ]; } // cuda12AsDefault)

  ## Cases CUDA 12 where cudaPackages from nvidia-jetpack6 is made the global default
  // mkAsserts ({ pkgsPath = [ "pkgsCudaDefault" "nvidia-jetpack6" "cudaPackages" "pkgs" ]; } // jetPack6AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCuda11" "nvidia-jetpack6" "cudaPackages" "pkgs" ]; } // jetPack6AsDefault)
  // mkAsserts ({ pkgsPath = [ "pkgsCuda12" "nvidia-jetpack" "cudaPackages" "pkgs" ]; } // jetPack6AsDefault)
    // mkAsserts ({ pkgsPath = [ "pkgsCuda12" "nvidia-jetpack6" "cudaPackages" "pkgs" ]; } // jetPack6AsDefault)
)
