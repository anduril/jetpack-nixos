{ buildFromDebs
, l4t-core
, l4tAtLeast
, lib
, wayland
,
}:
buildFromDebs {
  pname = "nvidia-l4t-wayland";
  buildInputs = [ wayland ] ++ lib.optionals (l4tAtLeast "38") [ l4t-core ];
  postPatch = ''
    sed -i -E "s#(libnvidia-egl-wayland)#$out/lib/\\1#" share/egl/egl_external_platform.d/nvidia_wayland.json
  '';
}
