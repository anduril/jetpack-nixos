{ buildFromDebs
, l4t-cuda
,
}:
buildFromDebs {
  pname = "nvidia-l4t-dla-compiler";
  repo = "common";
  buildInputs = [ l4t-cuda ];
}
