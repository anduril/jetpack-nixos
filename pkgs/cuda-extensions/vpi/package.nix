{ libcufft
, libnpp
, lib
, nvidia-jetpack
}:
let
  inherit (nvidia-jetpack)
    buildFromDebs
    debs
    l4t-3d-core
    l4t-core
    l4t-cupva
    l4t-multimedia
    l4t-pva
    l4t-video-codec-openrm
    l4tMajorMinorPatchVersion
    l4tOlder
    ;

  l4tMajorVersion = lib.versions.major l4tMajorMinorPatchVersion;
  majorVersion = lib.getAttr l4tMajorVersion {
    "35" = "2";
    "36" = "3";
    "38" = "4";
  };
in
buildFromDebs {
  pname = "vpi${majorVersion}";
  version = debs.common."vpi${majorVersion}-dev".version;
  srcs = [
    debs.common."libnvvpi${majorVersion}".src
    debs.common."vpi${majorVersion}-dev".src
  ];
  # Everything is deeply nested in opt, so we need to move it to the top-level.
  preDebNormalization = ''
    pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null
    mv --verbose --no-clobber "$PWD/opt/nvidia/vpi${majorVersion}"/* "$PWD/"
    nixLog "removing $PWD/opt"
    rm --recursive --dir "$PWD/opt" || {
      nixErrorLog "$PWD/opt contains non-empty directories: $(ls -laR "$PWD/opt")"
      exit 1
    }
    popd >/dev/null
  '';
  buildInputs = [
    l4t-core
    l4t-3d-core
    l4t-multimedia
    libcufft
    libnpp
  ]
  ++ lib.optional (l4tMajorVersion == "35") l4t-cupva
  ++ lib.optional (l4tMajorVersion == "36") l4t-pva
  ++ lib.optional (l4tMajorVersion == "38") l4t-video-codec-openrm;
  patches = [ ./vpi2.patch ];
  postPatch = ''
    rm -rf etc
    substituteInPlace lib/cmake/vpi/vpi-config.cmake --subst-var out
    substituteInPlace lib/cmake/vpi/vpi-config-release.cmake \
      --replace "lib/aarch64-linux-gnu" "lib/"
  '';
}
