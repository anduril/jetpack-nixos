{ buildFromDebs
, l4t-3d-core
, l4t-core
, mesa
,
}:
buildFromDebs {
  pname = "nvidia-l4t-gbm";
  buildInputs = [ l4t-core l4t-3d-core mesa ];
  postPatch = ''
    sed -i -E "s#(libnvidia-egl-gbm)#$out/lib/\\1#" share/egl/egl_external_platform.d/nvidia_gbm.json

    # Replace incorrect symlinks
    ln -sf ../libnvidia-allocator.so lib/gbm/nvidia-drm_gbm.so
    ln -sf ../libnvidia-allocator.so lib/gbm/tegra_gbm.so
    ln -sf ../libnvidia-allocator.so lib/gbm/tegra-udrm_gbm.so
  '';
}
