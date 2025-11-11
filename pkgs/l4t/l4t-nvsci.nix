{ buildFromDebs
, l4t-core
,
}:
buildFromDebs {
  pname = "nvidia-l4t-nvsci";
  buildInputs = [ l4t-core ];
}
