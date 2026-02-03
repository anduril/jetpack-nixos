{ autoPatchelfHook
, cmake
, cudaPackages
, debs
, dpkg
, l4tAtLeast
, l4t-pva
, lib
, opencv
}:
let
  inherit (cudaPackages)
    backendStdenv
    cuda_cudart
    cuda_nvcc
    vpi
    ;

  vpiMajor = lib.versions.major vpi.version;
in
backendStdenv.mkDerivation {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "vpi-samples";
  inherit (debs.common."vpi${vpiMajor}-samples") src version;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/opt/nvidia/vpi${vpiMajor}/samples";

  nativeBuildInputs = [ autoPatchelfHook cmake cuda_nvcc dpkg ];
  buildInputs = [ cuda_cudart opencv vpi ]
    ++ lib.optionals (l4tAtLeast "38") [ l4t-pva ];

  # Sample directories which we won't build.
  ignoredSampleDirs = {
    "11-fisheye" = if (lib.versionAtLeast opencv.version "4.10") then "1" else "0";
  };

  configurePhase = ''
    runHook preBuild

    for dirname in $(find . -type d | sort); do
      if [[ -e "$dirname/CMakeLists.txt" ]]; then
        [[ ''${ignoredSampleDirs["$(basename $dirname)"]-0} -eq 1 ]] && continue
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
        [[ ''${ignoredSampleDirs["$(basename $dirname)"]-0} -eq 1 ]] && continue
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
  '' + lib.optionalString (l4tAtLeast "38") ''
    # patchelf dlopen'd libraries so autoPatchelfHook can find them
    for exe in $out/bin/*; do
      patchelf \
        --add-needed libnvpvaumd_core.so \
        "$exe"
    done
    unset -v exe
  '' + ''

    runHook postInstall
  '';
}
