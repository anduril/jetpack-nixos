{ deb-builder }:
deb-builder {
  sourceName = "libcufft";
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
    name = "CUDA cuFFT";
  };
}
