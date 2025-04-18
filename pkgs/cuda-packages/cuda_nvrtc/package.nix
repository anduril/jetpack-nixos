{ deb-builder }:
deb-builder {
  sourceName = "cuda-nvrtc";
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
    name = "CUDA NVRTC";
  };
}
