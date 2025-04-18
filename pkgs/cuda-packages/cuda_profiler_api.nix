{ deb-builder }:
deb-builder {
  sourceName = "cuda-profiler-api";
  outputs = [
    "out"
    "dev"
    "doc"
    "include"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CUDA Profiler API";
  };
}
