{ deb-builder }:
deb-builder {
  sourceName = "libcurand";
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
    name = "CUDA cuRAND";
  };
}
