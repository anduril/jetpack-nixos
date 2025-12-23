{ dockerTools
, cudaPackages
, go
, lib
, writeText
, path
, writeTextFile
}:
let
  # we have support to build CUDA 11 and 12 containers and for amd64 (for all 3 major versions of CUDA)
  # only CUDA 13 arm64 is actually currently used. We can run the CUDA 11 and 12 containers
  # as part of OCI test in the future.

  # cuda "base" with only libcuda.so.1 and other essentials; used on device
  cudaBase = dockerTools.pullImage ({
    imageName = "nvidia/cuda";
  } // lib.getAttrFromPath [ cudaPackages.cudaMajorMinorVersion go.GOARCH ] {
    "13.0".amd64 = {
      finalImageTag = "13.0.2-base-ubuntu24.04";
      imageDigest = "sha256:605fb0c8acf8674e164d822da8a8521f3a655056e569f0899e72ae940e1fe7dc";
      sha256 = "";
    };
    "13.0".arm64 = {
      finalImageTag = "13.0.2-base-ubuntu24.04";
      imageDigest = "sha256:1ca86773be1716af6cfff3d2eb8cd10d4d9cac181931d1ee9be792d3e33c7322";
      sha256 = "sha256-IOtmpA2xiNL1/zodFdUz5/nrDYMBssDibwYE0uwrCcI= ";
    };
    "12.6".amd64 = {
      finalImageTag = "12.6.3-base-ubuntu24.04";
      imageDigest = "sha256:6b3201183858bad08441837f5a5efc2c75290135cc25fcc87d9ff763190cfd09";
      sha256 = "sha256-326qF7q4RtMnye/yOeh+lgilopoCrEJyV0WuTQlN9JM=";
    };
    "12.6".arm64 = {
      finalImageTag = "12.6.3-base-ubuntu24.04";
      imageDigest = "sha256:ba25600cea339517a8e55361a27535bbfdeae1936663e9b4970f3cec2fbbd165";
      sha256 = "sha256-lii+GS0havrQceqqYvHa35Lwe7I2rCQ3pVN5XvE2rmw=";
    };
    "11.8".amd64 = {
      finalImageTag = "11.8.0-base-ubuntu22.04";
      imageDigest = "sha256:79e5b2cf878ee9006f5b3738caeea34fdc7708a32db53fe3e80db0b48bd286a0";
      sha256 = "sha256-UHNlMC/LlQ6bJLMQ+tftDsvjxSgi+gmJvKoRbbH6CNA=";
    };
    "11.4".arm64 = {
      finalImageTag = "11.4.3-base-ubuntu20.04";
      imageDigest = "sha256:ef4813458a4b40b41f21c5fc505a7c7a39e12616273b2fb8ab10a1ebee541ac7";
      sha256 = "sha256-Oxx5w0OXq74oUHqaOYF2Xb4q8cxz2srhVvst+mFjC04=";
    };
  });

  # cuda "development" with libcuda and all the development tools; used to build saxpy the not-nixos way
  cudaDevel = dockerTools.pullImage ({
    imageName = "nvidia/cuda";
  } // lib.getAttrFromPath [ cudaPackages.cudaMajorMinorVersion go.GOARCH ] {
    "13.0".amd64 = {
      finalImageTag = "13.0.2-devel-ubuntu24.04";
      imageDigest = "sha256:0eee3094c71518ad31d011a594ae6ed6de72959ee07e318cb31cffe71690e90c";
      sha256 = "sha256-5PcPyKbIrNfHOsNJ8MCsBMSpVizR01qWaUtVsbEyqZE=";
    };
    "13.0".arm64 = {
      finalImageTag = "13.0.2-devel-ubuntu24.04";
      imageDigest = "sha256:450d11555d20ac8ebbbc13ebf17589c2bd42869171a90179ce7098b4a5e64c6a";
      sha256 = "sha256-fUwPPtLwAhU9UwxM59x35mboOPuxA1D6nV8N64I0uPI=";
    };
    "12.6".amd64 = {
      finalImageTag = "12.6.3-devel-ubuntu24.04";
      imageDigest = "sha256:badf6c452e8b1efea49d0bb956bef78adcf60e7f87ac77333208205f00ac9ade";
      sha256 = "sha256-P1XZZFmMP76XjZtagtNDXAlYcBR3OW+h/2fYMIMHCVM=";
    };
    "12.6".arm64 = {
      finalImageTag = "12.6.3-devel-ubuntu24.04";
      imageDigest = "sha256:37191266f9cad5651a92a4b56d8a03bb072bb27d768663e0fc9b6c7ecdfa0a11";
      sha256 = "sha256-+21AwCDcGtT3g3xcXi7wpzj3u1Wy7zRhFPumYVnfa+A=";
    };
    "11.8".amd64 = {
      finalImageTag = "11.8.0-devel-ubuntu22.04";
      imageDigest = "sha256:60eda04ab6790aa76d73bf0df245b361eabc6d8f7b6f6cf9846c70f399b9a1eb";
      sha256 = "sha256-PKn6U9m4jRXsnAxCLEw+BW3lYWdflKzLex2bA28ASa0=";
    };
    "11.4".arm64 = {
      finalImageTag = "11.4.3-devel-ubuntu20.04";
      imageDigest = "sha256:c5b82aac11fbba9f6d1a2802faa6739f597ba4ac3cdbd95205bd8e817dca74e3";
      sha256 = "sha256-oVILXM3crP2EwH/N+KhhAH2cm8Kwuihk705R88KNfcM=";
    };
  });

  saxpyLayer = dockerTools.mkRootLayer {
    name = "saxpy-builder";

    fromImage = cudaDevel;

    copyToRoot = [
      (path + "/pkgs/development/cuda-modules/packages/saxpy/src/")
    ];

    runAsRoot = ''
      /usr/local/cuda/bin/nvcc saxpy.cu
    '';

    # See nixpkgs/pkgs/build-support/docker/default.nix buildImage for construction of baseJson
    baseJson = writeText "saxpy-builder-config.json" (
      builtins.toJSON {
        created = "1970-01-01T00:00:01Z";
        config = null;
        architecture = go.GOARCH;
        preferLocalBuild = true;
        os = "linux";
      }
    );

    diskSize = 1024 * 20; # 20GB
    buildVMMemorySize = 2048; # 2GB
  };
in
dockerTools.buildLayeredImage {
  name = "oci-saxpy-container-test";
  fromImage = cudaBase;

  contents = [
    saxpyLayer

    (writeTextFile {
      name = "script-to-run-in-container";
      text = ''
        #!/bin/sh

        set -ex

        tar xf /layer.tar
        /a.out
      '';
      executable = true;
      destination = "/script-in-container";
    })
  ];

  config.cmd = [ "/script-in-container" ];
}
