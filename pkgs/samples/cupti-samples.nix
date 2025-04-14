{ autoAddDriverRunpath
, cudaPackages
, debs
, dpkg
, pkg-config
, stdenv
}:
stdenv.mkDerivation {
  pname = "cupti-samples";
  version = debs.common."cuda-cupti-dev-${cudaPackages.cudaVersionDashes}".version;
  src = debs.common."cuda-cupti-dev-${cudaPackages.cudaVersionDashes}".src;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/usr/local/cuda-${cudaPackages.cudaVersion}/extras/CUPTI/samples";

  nativeBuildInputs = [ dpkg pkg-config autoAddDriverRunpath ];
  buildInputs = [ cudaPackages.cudatoolkit ];

  preConfigure = ''
    export CUDA_INSTALL_PATH=${cudaPackages.cudatoolkit}
  '';

  enableParallelBuilding = true;

  buildPhase = ''
    runHook preBuild

    # Some samples depend on this being built first
    make $buildFlags -C extensions/src/profilerhost_util

    for sample in *; do
      if [[ "$sample" != "extensions" ]]; then
        make $buildFlags -C "$sample"
      fi
    done

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    for sample in *; do
      if [[ "$sample" != "extensions" && "$sample" != "autorange_profiling" && "$sample" != "userrange_profiling" ]]; then
        install -Dm755 -t $out/bin $sample/$sample
      fi
    done

    # These samples aren't named the same as their containing directory
    install -Dm755 -t $out/bin autorange_profiling/auto_range_profiling
    install -Dm755 -t $out/bin userrange_profiling/user_range_profiling

    runHook postInstall
  '';
}
