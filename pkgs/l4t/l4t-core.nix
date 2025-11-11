{ buildFromDebs
, expat
, libglvnd
, stdenv
,
}:
buildFromDebs {
  pname = "nvidia-l4t-core";
  buildInputs = [ stdenv.cc.cc.lib expat libglvnd ];
}
