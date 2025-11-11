{ buildFromDebs
, libgcc
,
}:
buildFromDebs {
  pname = "nvidia-l4t-adaruntime";
  buildInputs = [ libgcc ];
}
