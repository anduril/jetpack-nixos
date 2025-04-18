{ deb-builder }:
deb-builder {
  sourceName = "cuda-nvprune";
  outputs = [
    "out"
    "bin"
    "doc"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CUDA nvprune";
  };
}
