{ l4tMajorMinorPatchVersion
, dockerTools
, writeShellScriptBin
}:
let
  l4tImage = dockerTools.pullImage {
    imageName = "nvcr.io/nvidia/l4t-jetpack";
    imageDigest = "sha256:d1c8e971ab994235840eacc31c4ef4173bf9156317b1bf8aabe7e01eb21b2a0e";
    finalImageTag = "r35.4.1"; # As of 2024-10-27 there is (still) no 35.6.0 image published
    sha256 = "sha256-IDePYGssk6yrcaocnluxBaRJb7BrXxS7tBlEo6hNtHw=";
    os = "linux";
    arch = "arm64";
  };
in
{
  oci = writeShellScriptBin "oci-test" ''
    image=${l4tImage.imageName}:${l4tImage.imageTag}
    container_commands="cd /usr/local/cuda/samples/1_Utilities/deviceQuery && make && ./deviceQuery"

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
