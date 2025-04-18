{ deb-builder }:
deb-builder {
  sourceName = "tensorrt";
  fixupFns = [ ./fixup.nix ];
  outputs = [
    "out"
    "dev"
    "doc"
    "include"
    "lib"
    "static"
    "sample"
  ];
  releaseInfo = {
    license = "TensorRT";
    name = "NVIDIA TensorRT";
  };
}
