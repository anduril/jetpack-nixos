{ deb-builder }:
deb-builder {
  sourceName = "libcusparse";
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
    name = "CUDA cuSPARSE";
  };
}
