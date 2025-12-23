{ callPackage
, l4tMajorMinorPatchVersion
, lib
, writeShellScriptBin
}:
let
  l4tImage = callPackage ./container-r${lib.versions.major l4tMajorMinorPatchVersion}.nix { };
in
writeShellScriptBin "oci-test" ''
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
''
