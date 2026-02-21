{ alsa-lib
, buildFromDebs
, buildPackages
, cudaPackages
, debs
, defaultSomDebRepo
, dpkg
, fetchpatch
, fetchurl
, gst_all_1
, l4t-core
, l4t-cuda
, l4t-multimedia
, l4t-nvsci
, l4tAtLeast
, l4tOlder
, lib
, libv4l
, pango
}:
let
  inherit (cudaPackages) libnvjpeg;

  # Nvidia's included libv4l has very minimal changes against the upstream
  # version. We need to rebuild it from source to ensure it can find nvidia's
  # v4l plugins in the right location. Nvidia's version has the path hardcoded.
  # See https://gitlab.com/nvidia/nv-tegra/tegra/v4l2-src/v4l2_libs.git
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
in
buildFromDebs {
  pname = "nvidia-l4t-multimedia";
  srcs = [
    debs.${defaultSomDebRepo}.nvidia-l4t-multimedia.src
    debs.${defaultSomDebRepo}.nvidia-l4t-multimedia-utils.src
    debs.common.nvidia-l4t-jetson-multimedia-api.src
  ] ++ lib.optionals (l4tAtLeast "38") [
    debs.${defaultSomDebRepo}.nvidia-l4t-multimedia-openrm.src
    debs.${defaultSomDebRepo}.nvidia-l4t-multimedia-nvgpu.src
  ];
  buildInputs = [ l4t-core l4t-cuda l4t-nvsci pango alsa-lib ] ++ (with gst_all_1; [ gstreamer gst-plugins-base ]);

  patches = lib.optionals (l4tOlder "36") [
    (fetchpatch {
      url = "https://raw.githubusercontent.com/OE4T/meta-tegra/af0a93313c13e9eac4e80082d8a8e8ac5f7ad6e8/recipes-multimedia/argus/files/0005-Remove-DO-NOT-USE-declarations-from-v4l2_nv_extensio.patch";
      hash = "sha256-2PvlpGiz9evu3lc2R8nGYmC1jn8rqLo23dQ1cDvuCyo=";
      stripLen = 1;
      extraPrefix = "src/jetson_multimedia_api/";
    })
    (fetchpatch {
      url = "https://raw.githubusercontent.com/OE4T/meta-tegra/cc1c28f05fbd1b511d3bca3795dd9b6a35df5914/recipes-multimedia/argus/tegra-mmapi-samples/0004-samples-classes-fix-a-data-race-in-shutting-down-deq.patch";
      hash = "sha256-4Sm2kPP44LRPVMFrLmowvWPec1sIV2LHATsNmIGKExo=";
      stripLen = 1;
      extraPrefix = "src/jetson_multimedia_api/";
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
        ${lib.getExe buildPackages.patchelfUnstable} "$lib" \
          --rename-dynamic-symbols "$remapFile" \
          --replace-needed libnvos.so libnvos_multimedia.so
      fi
    done
  '';

  runtimeDependencies = [ l4t-nvsci ];
  # libnvmm_jpeg.so has a reference to libnvjpeg, which in JP6 is also present
  # in nvidia-l4t-multimedia. However, in JP7 this is now in a separate
  # libnvjpeg package
  appendRunpaths = [ "${placeholder "out"}/lib" ] ++ lib.optionals (l4tAtLeast "38") (builtins.map (p: (lib.getLib p) + "/lib") [ libnvjpeg ]);
}
