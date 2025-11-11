{ libcufft
, libnpp
, lib
, nvidia-jetpack
,
}:
let
  inherit (nvidia-jetpack)
    buildFromDebs
    debs
    l4t-3d-core
    l4t-core
    l4t-cupva
    l4t-multimedia
    l4tMajorMinorPatchVersion
    ;

  majorVersion = lib.getAttr (lib.versions.major l4tMajorMinorPatchVersion) {
    "35" = "2";
    "36" = "3";
  };
in
buildFromDebs {
  pname = "vpi${majorVersion}";
  version = debs.common."vpi${majorVersion}-dev".version;
  srcs = [
    debs.common."libnvvpi${majorVersion}".src
    debs.common."vpi${majorVersion}-dev".src
  ];
  sourceRoot = "source/opt/nvidia/vpi${majorVersion}";
  buildInputs = [
    l4t-core
    l4t-3d-core
    l4t-multimedia
    l4t-cupva
    libcufft
    libnpp
  ];
  patches = [ ./vpi2.patch ];
  postPatch = ''
    rm -rf etc
    substituteInPlace lib/cmake/vpi/vpi-config.cmake --subst-var out
    substituteInPlace lib/cmake/vpi/vpi-config-release.cmake \
      --replace "lib/aarch64-linux-gnu" "lib/"
  '';
}
