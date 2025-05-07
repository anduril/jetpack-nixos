{ deb-builder }:
deb-builder {
  sourceName = "libnvjitlink";
  packageName = "libnvjitlink";
  outputs = [
    "out"
    "dev"
    "include"
    "lib"
    "static"
    "stubs"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "libnvjitlink";
  };
}
