{ buildFromDebs
, buildPackages
, egl-wayland
, l4t-core
, lib
, libglvnd
, xorg
,
}:
# TODO: Split this package up into subpackages similar to what is done in meta-tegra: vulkan, glx, egl, etc
buildFromDebs {
  pname = "nvidia-l4t-3d-core";
  buildInputs = [ l4t-core libglvnd egl-wayland ];
  postPatch = ''
    # Replace incorrect ICD symlinks
    rm -rf etc
    mkdir -p share/vulkan/icd.d
    mv lib/nvidia_icd.json share/vulkan/icd.d/nvidia_icd.json
    # Use absolute path in ICD json
    sed -i -E "s#(libGLX_nvidia)#$out/lib/\\1#" share/vulkan/icd.d/nvidia_icd.json

    rm -f share/glvnd/egl_vendor.d/10_nvidia.json
    cp lib/tegra-egl/nvidia.json share/glvnd/egl_vendor.d/10_nvidia.json
    sed -i -E "s#(libEGL_nvidia)#$out/lib/\\1#" share/glvnd/egl_vendor.d/10_nvidia.json

    mv lib/tegra-egl/* lib
    rm -rf lib/tegra-egl
    rm -f lib/nvidia.json

    # Remove libnvidia-ptxjitcompiler, which is included in l4t-cuda instead
    rm -f lib/libnvidia-ptxjitcompiler.*

    # Some libraries, like libEGL_nvidia.so.0 from l4t-3d-core use a dlopen
    # wrapper called NvOsLibraryLoad, which originates in libnvos.so in
    # l4t-core. Unfortunately, calling dlopen from libnvos.so instead of the
    # original library/executable means that dlopen will use the DT_RUNPATH
    # from libnvos.so instead of the binary/library which called it. In ordo
    # to handle this, we make a copy of libnvos specifically for this package
    # so we can set the RUNPATH differently here. Additionally to avoid
    # linking conflicts we rename the library and NvOsLibraryLoad symbol.
    cp --no-preserve=ownership,mode ${l4t-core}/lib/libnvos.so lib/libnvos_3d.so
    patchelf --set-soname libnvos_3d.so lib/libnvos_3d.so

    remapFile=$(mktemp)
    echo NvOsLibraryLoad NvOsLibraryLoad_3d > $remapFile
    for lib in $(find ./lib -name "*.so*"); do
      if isELF $lib; then
        ${lib.getExe buildPackages.patchelfUnstable} "$lib" \
          --rename-dynamic-symbols "$remapFile" \
          --replace-needed libnvos.so libnvos_3d.so
      fi
    done
  '';

  appendRunpaths = [ "${placeholder "out"}/lib" ] ++ builtins.map (p: (lib.getLib p) + "/lib") [ libglvnd xorg.libX11 xorg.libXext xorg.libxcb ];
}
