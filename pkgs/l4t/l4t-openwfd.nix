{ buildFromDebs
, l4t-core
, l4t-nvsci
,
}:
buildFromDebs {
  pname = "nvidia-l4t-openwfd";
  buildInputs = [ l4t-core l4t-nvsci ];
}
