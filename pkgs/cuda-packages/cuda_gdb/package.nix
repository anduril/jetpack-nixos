{ deb-builder }:
deb-builder {
  sourceName = "cuda-gdb";
  # NOTE: Default unpacker throws away extras and python scripts.
  fixupFns = [ ./fixup.nix ];
  outputs = [
    "out"
    "bin"
    "doc"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CUDA GDB";
  };
}
