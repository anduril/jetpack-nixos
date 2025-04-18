{ deb-builder }:
deb-builder {
  sourceName = "cuda-nvml-dev";
  fixupFns = [ ./fixup.nix ];
  outputs = [
    "out"
    "dev"
    "doc"
    "include"
    "lib"
    "stubs"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CUDA NVML Headers";
  };
}
