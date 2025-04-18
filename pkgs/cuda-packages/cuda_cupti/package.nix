# NOTE: This derivation is meant only for Jetsons.
# Links were retrieved from https://repo.download.nvidia.com/jetson.
{ deb-builder }:
deb-builder {
  sourceName = "cuda-cupti";
  fixupFns = [ ./fixup.nix ];
  outputs = [
    "out"
    "dev"
    "doc"
    "include"
    "lib"
    "sample"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CUPTI";
  };
}
