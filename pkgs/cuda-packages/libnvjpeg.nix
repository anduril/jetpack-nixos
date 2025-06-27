{ deb-builder }:
deb-builder {
  sourceName = "libnvjpeg";
  packageName = "libnvjpeg";
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
    name = "libnvjpeg";
  };
}
