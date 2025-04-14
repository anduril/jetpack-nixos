{ autoAddDriverRunpath
, cudaPackages
, debs
, dpkg
, lib
, pkg-config
, stdenv
}:
let
  inherit (cudaPackages)
    cuda_nvcc
    cudatoolkit
    cudaMajorMinorVersion
    cudaVersionDashes
    flags
    ;
in
stdenv.mkDerivation {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "cupti-samples";
  inherit (debs.common."cuda-cupti-dev-${cudaVersionDashes}") src version;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/usr/local/cuda-${cudaMajorMinorVersion}/extras/CUPTI/samples";

  nativeBuildInputs = [ autoAddDriverRunpath cuda_nvcc dpkg pkg-config ];
  buildInputs = [ cudatoolkit ];

  makeFlags = [
    "CUDA_PATH=${cudatoolkit}"
    "SMS=${lib.replaceStrings [ ";" ] [" "] flags.cmakeCudaArchitecturesString}"
    # NOTE: CUDA_SEARCH_PATH is only ever used to find stubs.
    # Some packages (like deviceQueryDrv) try to link against driver stubs and are not built if they are not found.
    "CUDA_SEARCH_PATH=${cudatoolkit}/lib/stubs"
    # For some reason, CUPTI uses CUDA_INSTALL_PATH instead of CUDA_PATH.
    "CUDA_INSTALL_PATH=${cudatoolkit}"
  ];

  enableParallelBuilding = true;

  # Sample directories which we won't build.
  ignoredSampleDirs = {
    extensions = 1;
  };

  # In the case the sample directory doesn't match the name of the executable,
  # we can specify the name of the executable here.
  sampleExes = {
    autorange_profiling = "auto_range_profiling";
    userrange_profiling = "user_range_profiling";
  };

  # NOTE: flagsArray is copied from:
  # https://github.com/NixOS/nixpkgs/blob/96998d6c5cd4d47671d09cd5e4c6dccd00256648/pkgs/stdenv/generic/setup.sh#L1509-L1520
  buildPhase = ''
    runHook preBuild

    local flagsArray=(
      ''${enableParallelBuilding:+-j''${NIX_BUILD_CORES}}
      SHELL="$SHELL"
    )
    concatTo flagsArray makeFlags makeFlagsArray buildFlags buildFlagsArray
    echoCmd 'build flags' "''${flagsArray[@]}"

    # Some samples depend on this being built first
    make -C extensions/src/profilerhost_util "''${flagsArray[@]}"

    for sampleDir in *; do
      # Skip directories that don't exist or are ignored
      [[ ! -d $sampleDir || ''${ignoredSampleDirs["$sampleDir"]-0} -eq 1 ]] && continue
      pushd "$sampleDir"
      make "''${flagsArray[@]}"
      popd 2>/dev/null
    done
    unset -v sampleDir
    unset -v flagsArray

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    for sampleDir in *; do
      # Skip directories that don't exist or are ignored
      [[ ! -d $sampleDir || ''${ignoredSampleDirs["$sampleDir"]-0} -eq 1 ]] && continue
      # Install the sample, using the special name if it exists and the directory name if it doesn't.
      install -Dm755 -t "$out/bin" \
        "$sampleDir/''${sampleExes["$sampleDir"]:-"$sampleDir"}"
    done
    unset -v sampleDir

    runHook postInstall
  '';
}
