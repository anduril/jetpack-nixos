{ deb-builder }:
deb-builder {
  sourceName = "libcusparse";
  fixupFns = [ ./fixup.nix ];
  outputs = [
    "out"
    "dev"
    "doc"
    "include"
    "lib"
    "static"
    "stubs"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    name = "CUDA cuSPARSE";
  };
}
