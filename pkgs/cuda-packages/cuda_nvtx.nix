{ deb-builder }:
deb-builder {
  sourceName = "cuda-nvtx";
  outputs = [
    "out"
    "dev"
    "doc"
    "include"
    "lib"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CUDA NVTX";
  };
}
