{ buildFromDebs
, l4t-camera
, l4t-cuda
, l4t-multimedia
, l4tAtLeast
, wayland
}:
buildFromDebs {
  pname = "nvidia-l4t-gstreamer";
  repo = if l4tAtLeast "36" then "common" else "t234";
  buildInputs = [ l4t-camera l4t-cuda l4t-multimedia wayland ];
}
