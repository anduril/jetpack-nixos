{ deb-builder }:
deb-builder {
  sourceName = "cuda-nvdisasm";
  outputs = [
    "out"
    "bin"
    "doc"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CUDA nvdisasm";
  };
}
