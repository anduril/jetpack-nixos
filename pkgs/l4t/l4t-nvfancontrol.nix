{ buildFromDebs
, l4t-core
,
}:
buildFromDebs {
  pname = "nvidia-l4t-nvfancontrol";
  buildInputs = [ l4t-core ];
}
