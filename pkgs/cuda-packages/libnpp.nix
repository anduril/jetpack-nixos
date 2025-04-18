{ deb-builder }:
deb-builder {
  sourceName = "libnpp";
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
    name = "CUDA NPP";
  };
}
