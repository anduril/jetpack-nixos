{ deb-builder, cudaOlder }:
deb-builder {
  sourceName = "cuda-${if cudaOlder "12" then "thrust" else "cccl"}";
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
