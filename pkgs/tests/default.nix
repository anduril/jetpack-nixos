{ l4tMajorMinorPatchVersion
, dockerTools
, writeShellScriptBin
, lib
, l4tAtLeast
}:
let
  imageArgs = {
    "35" = {
      imageDigest = "sha256:d1c8e971ab994235840eacc31c4ef4173bf9156317b1bf8aabe7e01eb21b2a0e";
      finalImageTag = "r35.4.1"; # As of 2024-10-27 there is (still) no 35.6.0 image published
      sha256 = "sha256-IDePYGssk6yrcaocnluxBaRJb7BrXxS7tBlEo6hNtHw=";
    };
    "36" = {
      imageDigest = "sha256:34ccf0f3b63c6da9eee45f2e79de9bf7fdf3beda9abfd72bbf285ae9d40bb673";
      finalImageTag = "r36.4.0";
      sha256 = "sha256-+5+GRmyCl2ZcdYIJHU5snuFzEx1QkZic9bhtx9ZjXeo=";
    };
  };
  l4tImage = dockerTools.pullImage ({
    imageName = "nvcr.io/nvidia/l4t-jetpack";
    os = "linux";
    arch = "arm64";
  } // imageArgs.${lib.versions.major l4tMajorMinorPatchVersion});

  container_commands =
    if l4tAtLeast "36" then
      "apt-get update && apt-get install --yes cmake build-essential && wget https://github.com/NVIDIA/cuda-samples/archive/refs/tags/v12.9.tar.gz && tar xf v12.9.tar.gz && mkdir cuda-samples-12.9/build && cd cuda-samples-12.9/build && cmake -DBUILD_TEGRA=True .. ; make -C Samples/1_Utilities/deviceQuery && Samples/1_Utilities/deviceQuery/deviceQuery"
    else
      "cd /usr/local/cuda/samples/1_Utilities/deviceQuery && make && ./deviceQuery";
in
{
  oci = writeShellScriptBin "oci-test" ''
    image=${l4tImage.imageName}:${l4tImage.imageTag}
    container_commands="${container_commands}"

    for runtime in docker podman; do
      if command -v $runtime 2>&1 >/dev/null; then
        echo "testing $runtime runtime"
      else
        echo "$runtime runtime not found, skipping"
        continue
      fi

      "$runtime" load --input=${l4tImage}

      if "$runtime" run --rm "$image" bash -c "$container_commands"; then
        echo "container run w/o nvidia passthru unexpectedly succeeded"
        exit 1
      fi

      if ! "$runtime" run --rm --device=nvidia.com/gpu=all "$image" bash -c "$container_commands"; then
        echo "container run w/nvidia passthru unexpectedly failed"
        exit 1
      fi

      "$runtime" image rm "$image"
    done
  '';
}
