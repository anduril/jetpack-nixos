{ deb-builder }:
deb-builder {
  sourceName = "cuda-nvcc";
  fixupFns = [ ./fixup.nix ];
  outputs = [ "out" ]; # Use a single output to prevent consumers from doing the wrong things :l
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CUDA NVCC";
  };
}
