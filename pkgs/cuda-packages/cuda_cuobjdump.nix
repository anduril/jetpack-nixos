{ deb-builder }:
deb-builder {
  sourceName = "cuda-cuobjdump";
  outputs = [
    "out"
    "bin"
    "doc"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "cuobjdump";
  };
}
