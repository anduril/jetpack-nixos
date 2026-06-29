{ buildFromDebs
, l4t-core
, l4tMajorMinorPatchVersion
, lib
, libdrm
, wayland
,
}:
let
  l4tMajorVersion = lib.versions.major l4tMajorMinorPatchVersion;
in
buildFromDebs {
  pname = "nvidia-l4t-wayland";
  buildInputs = [ wayland ] ++ lib.optionals (l4tMajorVersion == "38") [ l4t-core ] ++ lib.optionals (l4tMajorVersion == "39") [ libdrm ];
  postPatch = ''
    sed -i -E "s#(libnvidia-egl-wayland)#$out/lib/\\1#" share/egl/egl_external_platform.d/nvidia_wayland.json
  '';
}
