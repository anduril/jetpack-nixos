{ buildFromDebs
, l4t-core
, l4t-cuda
, l4t-nvsci
,
}:
buildFromDebs {
  pname = "nvidia-l4t-pva";
  buildInputs = [ l4t-core l4t-cuda l4t-nvsci ];
}
