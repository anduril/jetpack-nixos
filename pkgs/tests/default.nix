{ l4tMajorMinorPatchVersion
, dockerTools
, writeShellScriptBin
, lib
, l4tAtLeast
, fetchFromGitHub
, buildEnv
, stdenv
, dlopenOverride
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
          tag = "v12.5"; # There is no 12.6 tag
          hash = "sha256-LL9A6olrpSAqePumNzQbAdljnzhOehmqqOy5sJieJk8=";
        };

        extraPrefix = "/share";
      in
      dockerTools.buildImage {
        name = "l4t-jetpack-with-samples";

        fromImage = dockerTools.pullImage {
          imageName = "nvcr.io/nvidia/l4t-jetpack";
          os = "linux";
          arch = "arm64";
          imageDigest = "sha256:34ccf0f3b63c6da9eee45f2e79de9bf7fdf3beda9abfd72bbf285ae9d40bb673";
          finalImageTag = "r36.4.0";
          sha256 = "sha256-+5+GRmyCl2ZcdYIJHU5snuFzEx1QkZic9bhtx9ZjXeo=";
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

  normal = stdenv.mkDerivation {
    name = "test-app";

    src = ./dlopen-libs;

    buildPhase = ''
      cc -shared -o lib1.so -fPIC test-lib1.c
      cc -shared -o lib2.so -fPIC test-lib2.c
      cc -o main test-app.c -ldl
    '';

    installPhase = ''
      install -Dm755 lib1.so "$out"/lib/lib1.so
      install -Dm755 lib2.so "$out"/lib/lib2.so
      install -Dm755 main "$out"/bin/main
    '';
  };

  override = stdenv.mkDerivation {
    name = "test-app-override";

    src = ./dlopen-libs;

    buildPhase = ''
      cc -shared -o lib1.so -fPIC test-lib1.c
      cc -shared -o lib2.so -fPIC test-lib2.c
      cc -o main test-app.c -ldl
    '';

    installPhase = ''
      install -Dm755 lib1.so "$out"/lib/lib1.so
      install -Dm755 lib2.so "$out"/lib/lib2.so
      install -Dm755 main "$out"/bin/main
    '';

    preFixup = ''
      postFixupHooks+=('
        ${ dlopenOverride { "./lib1.so" = "./lib2.so"; } "$out/bin/main" }
      ')
    '';
  };
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

  dlopen-override = writeShellScriptBin "dlopen-override-test" ''
    cd ${normal}/lib
    output=$(${normal}/bin/main)
    
    if [[ $output != "Hello, I am lib1" ]]; then
      echo "expected Hello, I am lib1 got $output" 
      exit 1
    fi

    cd ${override}/lib
    output=$(${override}/bin/main)
    
    if [[ $output != "Hello, I am lib2" ]]; then
      echo "expected Hello, I am lib2 got $output" 
      exit 1
    fi

    echo "dlopen-override is working as expected!"
  '';
}
