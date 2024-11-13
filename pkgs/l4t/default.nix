{ stdenv
, stdenvNoCC
, buildPackages
, addOpenGLRunpath
, lib
, fetchurl
, fetchpatch
, fetchgit
, autoPatchelfHook
, dpkg
, expat
, libglvnd
, egl-wayland
, xorg
, mesa
, wayland
, pango
, alsa-lib
, gst_all_1
, gtk3
, libv4l
, makeWrapper
, bc
, debs
, l4tVersion
}:
let
  # The version currently in nixpkgs 23.11 and master 0.15 is pretty old and
  # doesn't have the --rename-dynamic-symbols feature we need
  patchelf_new = buildPackages.patchelf.overrideAttrs (_: rec {
    version = "0.18.0";
    src = fetchurl {
      url = "https://github.com/NixOS/patchelf/releases/download/${version}/patchelf-${version}.tar.bz2";
      sha256 = "sha256-GVKyp4K6V2J5whHulC40F0j9tEmX9wTdU970bNBVRws=";
    };
  });

  # Wrapper around mkDerivation that has some sensible defaults to extract a .deb file from the L4T BSP pacckage
  buildFromDeb =
    # Nicely, the t194 and t234 packages are currently identical, so we just
    # use t194. No guarantee that will stay the same in the future, so we
    # should consider choosing the right package set based on the SoC.
    { name
    , src ? debs.t234.${name}.src
    , version ? debs.t234.${name}.version
    , sourceRoot ? "source"
    , nativeBuildInputs ? [ ]
    , autoPatchelf ? true
    , postPatch ? ""
    , ...
    }@args:
    stdenvNoCC.mkDerivation ((lib.filterAttrs (n: v: !(builtins.elem n [ "name" "autoPatchelf" ])) args) // {
      pname = name;
      inherit version src;

      nativeBuildInputs = [ dpkg ] ++ lib.optional autoPatchelf autoPatchelfHook ++ nativeBuildInputs;

      unpackCmd = "dpkg-deb -x $src source";
      inherit sourceRoot;

      dontConfigure = true;
      dontBuild = true;
      noDumpEnvVars = true;

      extraAutoPatchelfLibs = lib.optionals (autoPatchelf && (stdenv.buildPlatform != stdenv.hostPlatform)) [ "${stdenv.cc.cc.lib}/${stdenv.targetPlatform.config}/lib" ];

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
        runHook preInstall

        cp -r . $out

        runHook postInstall
      '';

      meta = {
        platforms = [ "aarch64-linux" ];
      } // (args.meta or { });
    });

  l4t-camera = buildFromDeb {
    name = "nvidia-l4t-camera";
    buildInputs = [ stdenv.cc.cc.lib l4t-core l4t-multimedia gtk3 ];
  };

  l4t-core = buildFromDeb {
    name = "nvidia-l4t-core";
    buildInputs = [ stdenv.cc.cc.lib expat libglvnd ];
  };

  # TODO: Split this package up into subpackages similar to what is done in meta-tegra: vulkan, glx, egl, etc
  l4t-3d-core = buildFromDeb {
    name = "nvidia-l4t-3d-core";
    buildInputs = [ l4t-core libglvnd egl-wayland ];
    postPatch = ''
      # Replace incorrect ICD symlinks
      #rm -rf etc
      #mkdir -p share/vulkan/icd.d
      #mv lib/nvidia_icd.json share/vulkan/icd.d/nvidia_icd.json
      # Use absolute path in ICD json
      #sed -i -E "s#(libGLX_nvidia)#$out/lib/\\1#" share/vulkan/icd.d/nvidia_icd.json

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

      #remove broken libcuda links
      echo remove broken libcuda links
      rm ./lib/libcuda.so
      
      for lib in $(find ./lib -name "*.so*"); do
        if isELF $lib; then
          ${patchelf_new}/bin/patchelf "$lib" \
            --rename-dynamic-symbols "$remapFile" \
            --replace-needed libnvos.so libnvos_3d.so
        fi
      done
    '';

    # We append a postFixupHook since we need to have this happen after
    # autoPatchelfHook, which itself also runs as a postFixupHook
    # TODO: Replace this with appendRunpaths which is available in 23.11
    preFixup = ''
      postFixupHooks+=('
        patchelf --add-rpath ${lib.makeLibraryPath [ libglvnd ]} \
          $out/lib/libEGL_nvidia.so.0 \
          $out/lib/libGLX_nvidia.so.0 \
          $out/lib/libnvidia-vulkan-producer.so

        patchelf --add-rpath ${lib.makeLibraryPath (with xorg; [ libX11 libXext libxcb ])} \
          $out/lib/libGLX_nvidia.so.0 \
          $out/lib/libnvidia-glsi.so.*

        for lib in $(find "$out/lib" -name "*.so*"); do
          patchelf $lib --add-rpath $out/lib
        done
      ')
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

      # Also unpack l4t-3d-core so we can grab libnvidia-ptxjitcompiler from it
      # and include it in this library.
      #
      # It's unclear why NVIDIA has this library in l4t-3d-core and not in
      # l4t-core. Even more so since the cuda compat package has libcuda as
      # well as libnvidia-ptxjitcompiler in the same package. meta-tegra does a
      # similar thing where they pull libnvidia-ptxjitcompiler out of
      # l4t-3d-core and place it in the same package as libcuda.
      dpkg --fsys-tarfile ${debs.t234.nvidia-l4t-3d-core.src} | tar -xO ./usr/lib/aarch64-linux-gnu/tegra/libnvidia-ptxjitcompiler.so.${l4tVersion} > lib/libnvidia-ptxjitcompiler.so.${l4tVersion}
      ln -sf libnvidia-ptxjitcompiler.so.${l4tVersion} lib/libnvidia-ptxjitcompiler.so.1
      ln -sf libnvidia-ptxjitcompiler.so.${l4tVersion} lib/libnvidia-ptxjitcompiler.so
    '';

    # libcuda.so actually depends on libnvcucompat.so at runtime (probably
    # through `dlopen`), so we need to tell Nix about this.
    postFixup = ''
      patchelf --add-needed libnvcucompat.so $out/lib/libcuda.so
    '';
  };

  l4t-cupva = buildFromDeb {
    name = "cupva";
    src = debs.common."cupva-2.3-l4t".src;
    version = debs.common."cupva-2.3-l4t".version;
    buildInputs = [ stdenv.cc.cc.lib l4t-cuda l4t-nvsci l4t-pva ];
    postPatch = ''
      mkdir -p lib
      mv opt/nvidia/cupva-2.3/lib/aarch64-linux-gnu/* lib/
      rm -rf opt
    '';
  };

  # TODO: Make nvwifibt systemd scripts work
  l4t-firmware = buildFromDeb {
    name = "nvidia-l4t-firmware";
    meta.platforms = [ "aarch64-linux" "x86_64-linux" ];
  };

  l4t-gbm = buildFromDeb {
    name = "nvidia-l4t-gbm";
    buildInputs = [ l4t-core l4t-3d-core mesa ];
    postPatch = ''
      sed -i -E "s#(libnvidia-egl-gbm)#$out/lib/\\1#" share/egl/egl_external_platform.d/nvidia_gbm.json

      # Replace incorrect symlinks
      ln -sf ../libnvidia-allocator.so lib/gbm/nvidia-drm_gbm.so
      ln -sf ../libnvidia-allocator.so lib/gbm/tegra_gbm.so
      ln -sf ../libnvidia-allocator.so lib/gbm/tegra-udrm_gbm.so
    '';
  };

  l4t-gstreamer = buildFromDeb {
    name = "nvidia-l4t-gstreamer";
    buildInputs = [ l4t-camera l4t-cuda l4t-multimedia wayland ];
  };

  # Most of the stuff in this package doesn't work in NixOS without
  # modification, so don't just include blindly. (for example, in
  # services.udev.packages)
  l4t-init = buildFromDeb {
    name = "nvidia-l4t-init";
    autoPatchelf = false;
  };

  # Nvidia's included libv4l has very minimal changes against the upstream
  # version. We need to rebuild it from source to ensure it can find nvidia's
  # v4l plugins in the right location. Nvidia's version has the path hardcoded.
  # See https://nv-tegra.nvidia.com/tegra/v4l2-src/v4l2_libs.git
  _l4t-multimedia-v4l = libv4l.overrideAttrs ({ nativeBuildInputs ? [ ], patches ? [ ], postPatch ? "", ... }: {
    nativeBuildInputs = nativeBuildInputs ++ [ dpkg ];
    patches = patches ++ lib.singleton (fetchurl {
      url = "https://raw.githubusercontent.com/OE4T/meta-tegra/85aa94e16104debdd01a3f61a521b73d86340a9f/recipes-multimedia/libv4l2/libv4l2-minimal/0003-Update-conversion-defaults-to-match-NVIDIA-sources.patch";
      sha256 = "sha256-gzWMilEbxkQfbArkCgFSYs9A06fdciCijYYCCpEiHOc=";
    });
    # Use a placeholder path that we replace in the l4t-multimedia derivation, We avoid an infinite recursion problem this way.
    postPatch = postPatch + ''
      substituteInPlace lib/libv4l2/v4l2-plugin.c \
        --replace LIBV4L2_PLUGIN_DIR '"/nix/store/00000000000000000000000000000000-${l4t-multimedia.name}/lib/libv4l/plugins/nv"'
    '';
  });

  l4t-multimedia = buildFromDeb {
    name = "nvidia-l4t-multimedia";
    # TODO: Replace the below with the builder from cuda-packages that works with multiple debs
    postUnpack = ''
      dpkg-deb -x ${debs.t234.nvidia-l4t-multimedia-utils.src} source
      dpkg-deb -x ${debs.common.nvidia-l4t-jetson-multimedia-api.src} source
    '';
    buildInputs = [ l4t-core l4t-cuda l4t-nvsci pango alsa-lib ] ++ (with gst_all_1; [ gstreamer gst-plugins-base ]);

    patches = [
      (fetchpatch {
        url = "https://raw.githubusercontent.com/OE4T/meta-tegra/af0a93313c13e9eac4e80082d8a8e8ac5f7ad6e8/recipes-multimedia/argus/files/0005-Remove-DO-NOT-USE-declarations-from-v4l2_nv_extensio.patch";
        sha256 = "sha256-meHF7uS2TFMoh0qGCmjGzR8hfhE0cCwSP2T3ufzwM0s=";
        stripLen = 1;
        extraPrefix = "usr/src/jetson_multimedia_api/";
      })
      (fetchpatch {
        url = "https://raw.githubusercontent.com/OE4T/meta-tegra/cc1c28f05fbd1b511d3bca3795dd9b6a35df5914/recipes-multimedia/argus/tegra-mmapi-samples/0004-samples-classes-fix-a-data-race-in-shutting-down-deq.patch";
        sha256 = "sha256-AasoKK4lQRgtVDkKlqS06jUzk99o+MajlxMoZzPGrSw=";
        stripLen = 1;
        extraPrefix = "usr/src/jetson_multimedia_api/";
      })
    ];
    postPatch = ''
      cp -r src/jetson_multimedia_api/{argus,include,samples} .
      rm -rf src

      # Replace nvidia's v4l libs with ours. Copy them instead of symlinking so we can modify them
      cp ${_l4t-multimedia-v4l}/lib/libv4l2.so lib/libnvv4l2.so
      cp ${_l4t-multimedia-v4l}/lib/libv4lconvert.so lib/libnvv4lconvert.so

      # Fix the placeholder path in the compiled v4l derivation
      sed -i "s#/nix/store/00000000000000000000000000000000-${l4t-multimedia.name}#$out#" lib/libnvv4l2.so lib/libnvv4lconvert.so

      # Fix a few broken symlinks
      ln -sf libnvv4l2.so lib/libv4l2.so.0.0.999999
      ln -sf libnvv4l2.so lib/libv4l2.so.0
      ln -sf libnvv4l2.so lib/libv4l2.so
      ln -sf libnvv4lconvert.so lib/libv4lconvert.so.0.0.999999
      ln -sf libnvv4lconvert.so lib/libv4lconvert.so.0
      ln -sf libnvv4lconvert.so lib/libv4lconvert.so

      ln -sf ../../../libv4l2_nvcuvidvideocodec.so lib/libv4l/plugins/nv/libv4l2_nvcuvidvideocodec.so
      ln -sf ../../../libv4l2_nvvideocodec.so lib/libv4l/plugins/nv/libv4l2_nvvideocodec.so

      # Make a copy of libnvos specifically for this package so we can set the RUNPATH differently here.
      # See note above for NvOsLibraryLoad
      cp --no-preserve=ownership,mode ${l4t-core}/lib/libnvos.so lib/libnvos_multimedia.so
      patchelf --set-soname libnvos_multimedia.so lib/libnvos_multimedia.so

      remapFile=$(mktemp)
      echo NvOsLibraryLoad NvOsLibraryLoad_multimedia > $remapFile
      for lib in $(find ./lib -name "*.so*"); do
        if isELF $lib; then
          ${patchelf_new}/bin/patchelf "$lib" \
            --rename-dynamic-symbols "$remapFile" \
            --replace-needed libnvos.so libnvos_multimedia.so
        fi
      done
    '';

    # We append a postFixupHook since we need to have this happen after
    # autoPatchelfHook, which itself also runs as a postFixupHook.
    # TODO: Use runtimeDependencies instead
    preFixup = ''
      postFixupHooks+=('
        patchelf --add-rpath ${lib.getLib l4t-nvsci}/lib $out/lib/libnvmedia*.so

        # dlopen in NvOsLibraryLoad from libnvos.so needs to be able to access these libraries
        patchelf --add-rpath $out/lib $out/lib/libnvos_multimedia.so
      ')
    '';
  };

  l4t-nvfancontrol = buildFromDeb {
    name = "nvidia-l4t-nvfancontrol";
    buildInputs = [ l4t-core ];
  };

  l4t-nvpmodel = buildFromDeb {
    name = "nvidia-l4t-nvpmodel";
    buildInputs = [ l4t-core ];
  };

  l4t-nvsci = buildFromDeb {
    name = "nvidia-l4t-nvsci";
    buildInputs = [ l4t-core ];
  };

  # Programmable Vision Accelerator
  l4t-pva = buildFromDeb {
    name = "nvidia-l4t-pva";
    buildInputs = [ l4t-core l4t-cuda l4t-nvsci ];
  };

  # For tegrastats and jetson_clocks
  l4t-tools = buildFromDeb {
    name = "nvidia-l4t-tools";
    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [ stdenv.cc.cc.lib l4t-core ];
    # Remove some utilities that bring in too many libraries
    postPatch = ''
      rm sbin/nv_wpa_supplicant_wifi
    '';
    postFixup = ''
      wrapProgram $out/bin/nv_fuse_read.sh --prefix PATH : ${lib.makeBinPath [ bc ]}
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
    meta.platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
in
{
  inherit
    ### Debs from L4T BSP
    l4t-3d-core
    l4t-camera
    l4t-core
    l4t-cuda
    l4t-cupva
    l4t-firmware
    l4t-gbm
    l4t-gstreamer
    l4t-init
    l4t-multimedia
    l4t-nvfancontrol
    l4t-nvpmodel
    l4t-nvsci
    l4t-pva
    l4t-tools
    l4t-wayland
    l4t-xusb-firmware;
}
