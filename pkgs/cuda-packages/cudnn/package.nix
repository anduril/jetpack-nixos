{ deb-builder }:
deb-builder {
  sourceName = "cudnn";
  fixupFns = [ ./fixup.nix ];
  outputs = [
    "out"
    "dev"
    "doc"
    "include"
    "lib"
    "static"
  ];
  releaseInfo = {
    license = "cudnn";
    name = "NVIDIA CUDA Deep Neural Network library";
  };
}
