{ buildFromDebs
,
}:
buildFromDebs {
  pname = "nvidia-l4t-firmware";
  meta.platforms = [ "aarch64-linux" "x86_64-linux" ];
}
