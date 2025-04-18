{ deb-builder }:
deb-builder {
  sourceName = "cuda-cuxxfilt";
  outputs = [
    "out"
    "bin"
    "dev"
    "doc"
    "include"
    "static"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CUPTI";
  };
}
