{ deb-builder }:
deb-builder {
  sourceName = "cuda-thrust";
  packageName = "cuda_cccl";
  outputs = [
    "out"
    "dev"
    "doc"
    "include"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CXX Core Compute Libraries";
  };
}
