{ buildFromDebs
, dlopenOverride
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

  # Unfortunately we have to do this dlopenOverride in postFixupHooks because autoPathElf and addDriverRunpaths override
  # the needed and rpath sections of the binary leading to our changes getting removed.
  preFixup = ''
    postFixupHooks+=('
      ${ dlopenOverride { "/usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0" = "/run/opengl-driver/lib/libEGL_nvidia.so.0"; } "$out/lib/libnvscf.so" }
      ${ dlopenOverride { "/usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0" = "/run/opengl-driver/lib/libEGL_nvidia.so.0"; } "$out/lib/libnvargus_socketclient.so" }
      ${ dlopenOverride { "/usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0" = "/run/opengl-driver/lib/libEGL_nvidia.so.0"; } "$out/lib/libnvargus.so" }
      ${ dlopenOverride { "/usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0" = "/run/opengl-driver/lib/libEGL_nvidia.so.0"; } "$out/lib/libnvargus_socketserver.so" }
    ')
  '';
}
