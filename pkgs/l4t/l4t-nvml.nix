{ buildFromDebs
, l4t-3d-core
, l4t-core
, l4tAtLeast
, lib
,
}:
buildFromDebs {
  pname = "nvidia-l4t-nvml";
  # libnvidia-ml.so.1 needs libnvidia-rmapi-tegra, which moved from
  # nvidia-l4t-core to nvidia-l4t-3d-core in r39.2.2.
  buildInputs = [ l4t-core ] ++ lib.optional (l4tAtLeast "39.2.2") l4t-3d-core;
  # nvidia-smi will dlopen libnvidia-ml.so.1
  appendRunpaths = [ "${placeholder "out"}/lib" ];
}
