{ buildFromDebs
,
}:
# Most of the stuff in this package doesn't work in NixOS without
# modification, so don't just include blindly. (for example, in
# services.udev.packages)
buildFromDebs {
  pname = "nvidia-l4t-init";
  autoPatchelf = false;
}
