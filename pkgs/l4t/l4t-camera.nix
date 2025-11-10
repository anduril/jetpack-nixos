{ buildFromDebs
, gtk3
, l4t-core
, l4t-multimedia
, stdenv
,
}:
buildFromDebs {
  pname = "nvidia-l4t-camera";
  buildInputs = [ stdenv.cc.cc.lib l4t-core l4t-multimedia gtk3 ];

  postPatch = ''
    ln -srfv lib/libv4l2_nvargus.so lib/libv4l/plugins/nv/libv4l2_nvargus.so
  '';
}
