{ dockerTools }:
dockerTools.buildImage {
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
}
