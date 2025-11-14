{ buildFromDebs
, l4t-adaruntime ? null
, l4t-core
, l4tAtLeast
, lib
,
}:
buildFromDebs {
  pname = "nvidia-l4t-nvsci";
  buildInputs = [ l4t-core ] ++ lib.optionals (l4tAtLeast "38") [ l4t-adaruntime ];
}
