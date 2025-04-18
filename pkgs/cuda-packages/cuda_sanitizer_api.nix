{ deb-builder }:
deb-builder {
  sourceName = "cuda-sanitizer-api";
  # TODO(@connorbaker): There's a bunch of stuff in usr/local/cuda-11.4/compute-sanitizer which looks important --
  # docs, headers, shared object files, etc. They're not copied over by the default unpacker.

  outputs = [
    "out"
    "bin"
    "doc"
  ];
  releaseInfo = {
    license = "CUDA Toolkit";
    licensePath = null;
    name = "CUDA Compute Sanitizer API";
    version = "11.4.298";
  };
}
