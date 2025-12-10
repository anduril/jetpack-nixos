{ autoAddDriverRunpath
, autoPatchelfHook
, cairo
, cudaPackages
, debs
, dpkg
, fetchurl
, l4t-camera
, l4t-cuda
, l4t-multimedia
, l4t-pva
, l4t-video-codec-openrm ? null
, l4tAtLeast
, l4tMajorMinorPatchVersion
, lib
, libdrm
, libglvnd
, opencv
, pango
, python3
, vulkan-headers
, vulkan-loader
, xorg
}:
# https://docs.nvidia.com/jetson/l4t-multimedia/group__l4t__mm__test__group.html
let
  inherit (cudaPackages)
    backendStdenv
    cuda_nvcc
    cudatoolkit
    libnvjpeg
    tensorrt
    ;
  inherit (xorg) libX11;
in
backendStdenv.mkDerivation {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "multimedia-samples";
  inherit (debs.common.nvidia-l4t-jetson-multimedia-api) src version;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/usr/src/jetson_multimedia_api";

  nativeBuildInputs = [ autoAddDriverRunpath autoPatchelfHook cuda_nvcc dpkg python3 ];
  buildInputs = [
    cairo
    cudatoolkit
    l4t-camera
    l4t-cuda
    l4t-multimedia
    libdrm
    libglvnd
    libX11
    opencv
    pango
    tensorrt
    vulkan-headers
    vulkan-loader
  ] ++ lib.optionals (l4tAtLeast "38") [
    libnvjpeg
    l4t-video-codec-openrm
    l4t-pva
  ];

  # Usually provided by pkg-config, but the samples don't use it.
  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-I${lib.getDev libdrm}/include/libdrm"
    "-I${lib.getDev opencv}/include/opencv4"
  ];

  # TODO: Unify this with headers in l4t-jetson-multimedia-api
  patches =
    (lib.getAttr (lib.versions.major l4tMajorMinorPatchVersion) {
      "35" = [
        (fetchurl {
          url = "https://raw.githubusercontent.com/OE4T/meta-tegra/af0a93313c13e9eac4e80082d8a8e8ac5f7ad6e8/recipes-multimedia/argus/files/0005-Remove-DO-NOT-USE-declarations-from-v4l2_nv_extensio.patch";
          sha256 = "sha256-IJ1teGEUxYDEPYSvYZbqdmUYg9tOORN7WGYpDaUUnHY=";
        })
      ];
      "36" = [
        (fetchurl {
          url = "https://raw.githubusercontent.com/OE4T/meta-tegra/2b51abd5b3e2436f8eeb98e8f985806521379174/recipes-multimedia/argus/files/0001-Remove-DO-NOT-USE-declarations-from-v4l2_nv_extensio.patch";
          sha256 = "sha256-J9Hhm7oOptUR39KMbxZB1+esAlKWTyyKk1Ep3ZlJ488=";
        })
      ];
      "38" = [
        (fetchurl {
          url = "https://raw.githubusercontent.com/OE4T/meta-tegra/992c0f9e170ad1e60aa3272ecb2db0e4f967a576/recipes-multimedia/argus/files/0001-Remove-DO-NOT-USE-declarations-from-v4l2_nv_extensio.patch";
          sha256 = "sha256-BXvugEROOgVU+zzuusHSZ0N/4Usl3vqw0tXbeGbzekA=";
        })
      ];
    })
    ++ [
      (fetchurl {
        url = "https://raw.githubusercontent.com/OE4T/meta-tegra/4f825ddeb2e9a1b5fbff623955123c20b82c8274/recipes-multimedia/argus/tegra-mmapi-samples/0004-samples-classes-fix-a-data-race-in-shutting-down-deq.patch";
        sha256 = "sha256-mkS2eKuDvXDhHkIglUGcYbEWGxCP5gRSdmEvuVw/chI=";
      })
    ];

  postPatch = ''
    substituteInPlace samples/Rules.mk \
      --replace-fail /usr/local/cuda "${cudatoolkit}"

    substituteInPlace samples/08_video_dec_drm/Makefile \
      --replace-fail /usr/bin/python "${python3}/bin/python"
  '';

  installPhase = ''
    runHook preInstall

    install -Dm 755 -t $out/bin $(find samples -type f -perm 755)
    rm -f $out/bin/*.h

    cp -r data $out/

    # patchelf dlopen'd libraries so autoPatchelfHook can find them
    for exe in $out/bin/*; do
      patchelf \
        --add-needed libcairo.so.2 \
        --add-needed libgobject-2.0.so.0 \
        --add-needed libpango-1.0.so.0 \
        --add-needed libpangocairo-1.0.so.0 \
        ${lib.optionalString (l4tAtLeast "38") ''
          --add-needed libnvjpeg.so.13 \
          --add-needed libnvcuvid.so.1 \
          --add-needed libnvidia-encode.so.1 \
          --add-needed libnvpvaumd_core.so \
        ''} \
        "$exe"
    done
    unset -v exe

    runHook postInstall
  '';
}
