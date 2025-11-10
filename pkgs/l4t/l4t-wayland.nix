{ buildFromDebs
, wayland
,
}:
buildFromDebs {
  pname = "nvidia-l4t-wayland";
  buildInputs = [ wayland ];
  postPatch = ''
    sed -i -E "s#(libnvidia-egl-wayland)#$out/lib/\\1#" share/egl/egl_external_platform.d/nvidia_wayland.json
  '';
}
