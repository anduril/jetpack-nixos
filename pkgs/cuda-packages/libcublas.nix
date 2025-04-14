{ deb-builder }:
deb-builder {
  sourceName = "libcublas";
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
    name = "CUDA cuBLAS";
  };
}
