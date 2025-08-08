{ l4tMajorMinorPatchVersion
, dockerTools
, writeShellScriptBin
, lib
, l4tAtLeast
, fetchFromGitHub
, buildEnv
}:
# https://docs.nvidia.com/jetson/archives/r36.4.4/DeveloperGuide/SD/TestPlanValidation.html#nvidia-containers
let
  l4tImage = {
    "35" = dockerTools.buildImage {
      name = "l4t-jetpack-with-samples";

      fromImage = dockerTools.pullImage {
        imageName = "nvcr.io/nvidia/l4t-jetpack";
        os = "linux";
        arch = "arm64";
        imageDigest = "sha256:d1c8e971ab994235840eacc31c4ef4173bf9156317b1bf8aabe7e01eb21b2a0e";
        finalImageTag = "r35.4.1"; # As of 2024-10-27 there is (still) no 35.6.0 image published
        sha256 = "sha256-IDePYGssk6yrcaocnluxBaRJb7BrXxS7tBlEo6hNtHw=";
      };

      config.cmd = [ "bash" "-c" "cd /usr/local/cuda/samples/1_Utilities/deviceQuery && make && ./deviceQuery" ];
    };
    "36" =
      let
        cuda-samples = fetchFromGitHub {
          owner = "NVIDIA";
          repo = "cuda-samples";
          tag = "v12.2";
          sha256 = "sha256-3+1gFQfrfv66dWeclA+905nsmOYstf36iPcBSAQToTo=";
        };

        extraPrefix = "/share";
      in
      dockerTools.buildImage {
        name = "l4t-jetpack-with-samples";

        fromImage = dockerTools.pullImage {
          imageName = "nvcr.io/nvidia/l4t-jetpack";
          os = "linux";
          arch = "arm64";
          imageDigest = "sha256:b3bbd7e3f3a0879a6672adc64aef7742ba12f9baaf1451c91215942c46e4e2fa";
          finalImageTag = "r36.3.0";
          sha256 = "sha256-gPNavdjoShqg8jTlAmWJiAqPqT/KXtU+BFSlxhSBQx4=";
        };

        copyToRoot = [
          (buildEnv {
            name = "cuda-samples-fhs";
            paths = [ cuda-samples ];
            inherit extraPrefix;
          })
        ];

        config.Cmd = [ "bash" "-c" "make -C ${extraPrefix}/Samples/1_Utilities/deviceQuery && ${extraPrefix}/Samples/1_Utilities/deviceQuery/deviceQuery" ];
      };
  }.${lib.versions.major l4tMajorMinorPatchVersion};
in
{
  oci = writeShellScriptBin "oci-test" ''
    image=${l4tImage.imageName}:${l4tImage.imageTag}

    for runtime in docker podman; do
      if command -v $runtime 2>&1 >/dev/null; then
        echo "testing $runtime runtime"
      else
        echo "$runtime runtime not found, skipping"
        continue
      fi

      echo "loading image ${l4tImage} with tag $image..."
      "$runtime" load --input=${l4tImage}
      echo "loaded image"

      echo "testing without NVIDIA passthru, which should fail"
      if "$runtime" run --rm "$image"; then
        echo "container run without NVIDIA passthru unexpectedly succeeded"
        exit 1
      fi
      echo "test without NVIDIA passthru failed, as expected"

      echo "testing with NVIDIA passthru, which should succeed"
      if ! "$runtime" run --rm --device=nvidia.com/gpu=all "$image"; then
        echo "container run with NVIDIA passthru unexpectedly failed"
        exit 1
      fi
      echo "test with NVIDIA passthru succeeded, as expected"

      echo "removing image $image..."
      "$runtime" image rm "$image"
      echo "removed image $image"

      echo "finished testing $runtime"
    done
  '';
}
