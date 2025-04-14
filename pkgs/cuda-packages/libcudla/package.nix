{ deb-builder }:
deb-builder {
  sourceName = "libcudla";
  fixupFns = [ ./fixup.nix ];
  outputs = [
    "out"
    "dev"
    "doc"
    "include"
    "lib"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "cuDLA";
  };
}
