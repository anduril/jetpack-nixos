{ buildFromDebs
, l4t-core
,
}:
buildFromDebs {
  pname = "nvidia-l4t-video-codec-openrm";
  buildInputs = [ l4t-core ];
}
