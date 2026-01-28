{ buildFromDebs
, debs
, elfutils
, ffmpeg_6
, glib
, gst_all_1
, gtk2
, gtk3
, libjpeg8
, libunwind
, onetbb
, orc
, zstd
,
}:
buildFromDebs {
  pname = "nvidia-opencv";
  version = debs.common.libopencv.version;
  srcs = [
    debs.common.libopencv.src
    debs.common.libopencv-dev.src
    debs.common.nvidia-opencv.src
    debs.common.nvidia-opencv-dev.src
  ];

  postPatch = ''
    substituteInPlace lib/pkgconfig/opencv4.pc --replace-fail "prefix=/usr/local" "prefix=${placeholder "out"}"
  '';

  buildInputs = [
    glib
    gtk2
    gtk3
    elfutils
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gstreamer
    libunwind
    orc
    zstd
    onetbb
    libjpeg8
    ffmpeg_6
  ];
}
