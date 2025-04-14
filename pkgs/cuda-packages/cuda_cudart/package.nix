# NOTE: This derivation is meant only for Jetsons.
# Links were retrieved from https://repo.download.nvidia.com/jetson.
{ deb-builder }:
deb-builder {
  sourceName = "cuda-cudart";
  fixupFns = [ ./fixup.nix ];
  outputs = [
    "out"
    "dev"
    "doc"
    "include"
    "lib"
    "static"
    "stubs"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CUDA Runtime (cudart)";
  };
}
