{ cmake
, cudaPackages
, debs
, dpkg
, opencv
, stdenv
}:
# Tested via "./result/bin/vpi_sample_05_benchmark <cpu|pva|cuda>" (Try pva especially)
# Getting a bunch of "pva 16000000.pva0: failed to get firmware" messages, so unsure if its working.
stdenv.mkDerivation {
  pname = "vpi2-samples";
  version = debs.common.vpi2-samples.version;
  src = debs.common.vpi2-samples.src;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/opt/nvidia/vpi2/samples";

  nativeBuildInputs = [ dpkg cmake ];
  buildInputs = [ opencv ] ++ (with cudaPackages; [ vpi2 ]);

  configurePhase = ''
    runHook preBuild

    for dirname in $(find . -type d | sort); do
      if [[ -e "$dirname/CMakeLists.txt" ]]; then
        echo "Configuring $dirname"
        pushd $dirname
        cmake .
        popd 2>/dev/null
      fi
    done

    runHook postBuild
  '';

  buildPhase = ''
    runHook preBuild

    for dirname in $(find . -type d | sort); do
      if [[ -e "$dirname/CMakeLists.txt" ]]; then
        echo "Building $dirname"
        pushd $dirname
        make $buildFlags
        popd 2>/dev/null
      fi
    done

    runHook postBuild
  '';

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    install -Dm 755 -t $out/bin $(find . -type f -maxdepth 2 -perm 755)

    runHook postInstall
  '';
}
