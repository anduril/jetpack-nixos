{ buildFromDebs
,
}:
buildFromDebs {
  pname = "nvidia-l4t-xusb-firmware";
  autoPatchelf = false;
  meta.platforms = [ "aarch64-linux" "x86_64-linux" ];
}
