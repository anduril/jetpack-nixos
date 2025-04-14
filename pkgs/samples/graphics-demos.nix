{ coreutils
, debs
, dpkg
, gnused
, libdrm
, libffi
, libGL
, libxkbcommon
, stdenv
, wayland
, xorg
}:
# TODO: Add wayland and x11 tests for graphics demos....
let
  inherit (xorg) libX11 libXau;
in
stdenv.mkDerivation {
  pname = "graphics-demos";
  inherit (debs.t234.nvidia-l4t-graphics-demos) src version;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/usr/src/nvidia/graphics_demos";

  nativeBuildInputs = [ dpkg ];
  buildInputs = [ libX11 libGL libXau libdrm wayland libxkbcommon libffi ];

  postPatch = ''
    substituteInPlace Makefile.l4tsdkdefs \
      --replace /bin/cat ${coreutils}/bin/cat \
      --replace /bin/sed ${gnused}/bin/sed \
      --replace libffi.so.7 libffi.so
  '';

  buildPhase = ''
    runHook preBuild

    # TODO: Also do winsys=egldevice
    for winsys in wayland x11; do
      for demo in bubble ctree eglstreamcube gears-basic gears-cube gears-lib; do
        pushd "$demo"
        make NV_WINSYS=$winsys NV_PLATFORM_LDFLAGS= $buildFlags
        popd 2>/dev/null
      done
    done

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    for winsys in wayland x11; do
      for demo in bubble ctree eglstreamcube; do
        install -Dm 755 "$demo/$winsys/$demo" "$out/bin/$winsys-$demo"
      done
      install -Dm 755 "gears-basic/$winsys/gears" "$out/bin/$winsys-gears"
      install -Dm 755 "gears-cube/$winsys/gearscube" "$out/bin/$winsys-gearscube"
    done

    runHook postInstall
  '';

  enableParallelBuilding = true;
}
