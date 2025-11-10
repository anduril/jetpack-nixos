{ buildFromDebs
, l4t-core
,
}:
buildFromDebs {
  pname = "nvidia-l4t-nvml";
  buildInputs = [ l4t-core ];
  # nvidia-smi will dlopen libnvidia-ml.so.1
  appendRunpaths = [ "${placeholder "out"}/lib" ];
}
