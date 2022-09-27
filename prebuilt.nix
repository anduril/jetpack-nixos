{ stdenv, stdenvNoCC, lib, fetchurl, autoPatchelfHook,
  dpkg, expat, libglvnd, egl-wayland, xorg, mesa, wayland,
  pango, alsa-lib, gst_all_1,

  debs, l4tVersion
}:
let
  # Wrapper around mkDerivation that has some sensible defaults to extract a .deb file from the L4T BSP pacckage
  buildFromDeb =
    # Nicely, the t194 and t234 packages are currently identical, so we just
    # use t194. No guarantee that will stay the same in the future, so we
    # should consider choosing the right package set based on the SoC.
    { name, src ? debs.t234.${name}.src, version ? debs.t234.${name}.version,
      nativeBuildInputs ? [], autoPatchelf ? true, postPatch ? "", ...
    }@args:
    stdenvNoCC.mkDerivation ((lib.filterAttrs (n: v: !(builtins.elem n [ "name" "autoPatchelf" ])) args) // {
      pname = "l4t-${name}";
      inherit version src;

      nativeBuildInputs = [ dpkg ] ++ lib.optional autoPatchelf autoPatchelfHook ++ nativeBuildInputs;

      unpackCmd = "dpkg-deb -x $src ./";
      sourceRoot = ".";

      dontConfigure = true;
      dontBuild = true;
      noDumpEnvVars = true;

      postPatch = ''
        if [[ -d usr ]]; then
          mv usr/* .
          rmdir usr
        fi

        if [[ -d lib/aarch64-linux-gnu ]]; then
          mv lib/aarch64-linux-gnu/* lib
          rm -rf lib/aarch64-linux-gnu
        fi

        if [[ -d lib/tegra ]]; then
          mv lib/tegra/* lib
          rm -rf lib/tegra
        fi

        ${postPatch}

        rm -f lib/ld.so.conf
      '';

      installPhase = ''
        cp -r . $out
      '';
    });


  l4t-core = buildFromDeb {
    name = "nvidia-l4t-core";
    buildInputs = [ stdenv.cc.cc.lib expat libglvnd ];
  };

  l4t-3d-core = buildFromDeb {
    name = "nvidia-l4t-3d-core";
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

      # Make some symlinks also done by OE4T
      ln -sf libnvidia-ptxjitcompiler.so.${l4tVersion} lib/libnvidia-ptxjitcompiler.so.1
      ln -sf libnvidia-ptxjitcompiler.so.${l4tVersion} lib/libnvidia-ptxjitcompiler.so
    '';

    # Re-add needed paths to RPATH
    autoPatchelf = false;
    postFixup = ''
      for lib in $(find "$out/lib" -name '*.so*'); do
        patchelf $lib --set-rpath $out/lib:${lib.makeLibraryPath [ l4t-core libglvnd egl-wayland xorg.libX11 xorg.libXext ]}
      done
    '';
  };

  # CUDA driver
  l4t-cuda = buildFromDeb {
    name = "nvidia-l4t-cuda";
    buildInputs = [ l4t-core ];
    postPatch = ''
      # Additional libcuda symlinks
      ln -sf libcuda.so.1.1 lib/libcuda.so.1
      ln -sf libcuda.so.1.1 lib/libcuda.so
    '';
  };

  # TODO: Make nvwifibt systemd scripts work
  l4t-firmware = buildFromDeb {
    name = "nvidia-l4t-firmware";
  };

  l4t-gbm = buildFromDeb {
    name = "nvidia-l4t-gbm";
    buildInputs = [ l4t-core l4t-3d-core mesa ];
    postPatch = ''
      rm -rf lib/gbm # These are just symlinks
      sed -i -E "s#(libnvidia-egl-gbm)#$out/lib/\\1#" share/egl/egl_external_platform.d/nvidia_gbm.json
    '';
  };

  # Most of the stuff in this package doesn't work in NixOS without
  # modification, so don't just include blindly. (for example, in
  # services.udev.packages)
  l4t-init = buildFromDeb {
    name = "nvidia-l4t-init";
    autoPatchelf = false;
  };

  # TODO: build and test multimedia samples from nvidia-l4t-jetson-multimedia-api
  l4t-multimedia = buildFromDeb {
    name = "nvidia-l4t-multimedia";
    # TODO: Replace the below with the builder from cuda-packages that works with multiple debs
    postUnpack = "dpkg-deb -x ${debs.t234.nvidia-l4t-multimedia-utils.src} .";
    buildInputs = [ l4t-core l4t-cuda l4t-nvsci pango alsa-lib ] ++ (with gst_all_1; [ gstreamer gst-plugins-base ]);
    # Fix a couple broken symlinks
    postPatch = ''
      ln -sf libnvv4l2.so lib/libv4l2.so.0.0.999999
      ln -sf libnvv4l2.so lib/libv4l2.so.0
      ln -sf libnvv4lconvert.so lib/libv4lconvert.so.0.0.999999
      ln -sf libnvv4lconvert.so lib/libv4lconvert.so.0
    '';
  };

  l4t-nvpmodel = buildFromDeb {
    name = "nvidia-l4t-nvpmodel";
  };

  l4t-nvsci = buildFromDeb {
    name = "nvidia-l4t-nvsci";
    buildInputs = [ l4t-core ];
  };

  # For tegrastats and jetson_clocks
  l4t-tools = buildFromDeb {
    name = "nvidia-l4t-tools";
    buildInputs = [ stdenv.cc.cc.lib l4t-core ];
    # Remove some utilities that bring in too many libraries
    postPatch = ''
      rm bin/nv_macsec_wpa_supplicant
    '';
  };

  l4t-wayland = buildFromDeb {
    name = "nvidia-l4t-wayland";
    buildInputs = [ wayland ];
    postPatch = ''
      sed -i -E "s#(libnvidia-egl-wayland)#$out/lib/\\1#" share/egl/egl_external_platform.d/nvidia_wayland.json
    '';
  };

  l4t-xusb-firmware = buildFromDeb {
    name = "nvidia-l4t-xusb-firmware";
    autoPatchelf = false;
  };
in {
  inherit
    ### Debs from L4T BSP
    l4t-3d-core
    l4t-core
    l4t-cuda
    l4t-firmware
    l4t-gbm
    l4t-init
    l4t-multimedia
    l4t-nvpmodel
    l4t-nvsci
    l4t-tools
    l4t-wayland
    l4t-xusb-firmware;
}
