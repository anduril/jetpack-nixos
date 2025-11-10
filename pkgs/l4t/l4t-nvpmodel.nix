{ buildFromDebs
, l4t-core
,
}:
buildFromDebs {
  pname = "nvidia-l4t-nvpmodel";
  buildInputs = [ l4t-core ];
}
