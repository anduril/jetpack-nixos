{ cudaPackages
, debs
, dpkg
, fetchurl
, l4t-camera
, l4t-cuda
, l4t-multimedia
, lib
, libdrm
, libglvnd
, libX11
, opencv
, python3
, stdenv
, vulkan-headers
, vulkan-loader
}:
# https://docs.nvidia.com/jetson/l4t-multimedia/group__l4t__mm__test__group.html
stdenv.mkDerivation {
  pname = "multimedia-samples";
  src = debs.common.nvidia-l4t-jetson-multimedia-api.src;
  version = debs.common.nvidia-l4t-jetson-multimedia-api.version;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/usr/src/jetson_multimedia_api";

  nativeBuildInputs = [ dpkg python3 ];
  buildInputs = [ libX11 libdrm libglvnd opencv vulkan-headers vulkan-loader ]
    ++ ([ l4t-cuda l4t-multimedia l4t-camera ])
    ++ (with cudaPackages; [ cudatoolkit tensorrt ]);

  # Usually provided by pkg-config, but the samples don't use it.
  NIX_CFLAGS_COMPILE = [
    "-I${lib.getDev libdrm}/include/libdrm"
    "-I${lib.getDev opencv}/include/opencv4"
  ];

  # TODO: Unify this with headers in l4t-jetson-multimedia-api
  patches = [
    (fetchurl {
      url = "https://raw.githubusercontent.com/OE4T/meta-tegra/af0a93313c13e9eac4e80082d8a8e8ac5f7ad6e8/recipes-multimedia/argus/files/0005-Remove-DO-NOT-USE-declarations-from-v4l2_nv_extensio.patch";
      sha256 = "sha256-IJ1teGEUxYDEPYSvYZbqdmUYg9tOORN7WGYpDaUUnHY=";
    })
    (fetchurl {
      url = "https://raw.githubusercontent.com/OE4T/meta-tegra/4f825ddeb2e9a1b5fbff623955123c20b82c8274/recipes-multimedia/argus/tegra-mmapi-samples/0004-samples-classes-fix-a-data-race-in-shutting-down-deq.patch";
      sha256 = "sha256-mkS2eKuDvXDhHkIglUGcYbEWGxCP5gRSdmEvuVw/chI=";
    })
  ];

  postPatch = ''
    substituteInPlace samples/Rules.mk \
      --replace /usr/local/cuda "${cudaPackages.cudatoolkit}"

    substituteInPlace samples/08_video_dec_drm/Makefile \
      --replace /usr/bin/python "${python3}/bin/python"
  '';

  installPhase = ''
    runHook preInstall

    install -Dm 755 -t $out/bin $(find samples -type f -perm 755)
    rm -f $out/bin/*.h

    cp -r data $out/

    runHook postInstall
  '';
}
