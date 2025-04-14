{ autoAddDriverRunpath
, cudaPackages
, debs
, dpkg
, lib
, stdenv
}:
let
  inherit (cudaPackages)
    cuda_nvcc
    cudatoolkit
    cudnn
    flags
    ;
in
stdenv.mkDerivation {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "cudnn-samples";
  inherit (debs.common.libcudnn8-samples) src version;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/usr/src/cudnn_samples_v8";

  nativeBuildInputs = [ autoAddDriverRunpath cuda_nvcc dpkg ];
  buildInputs = [ cudatoolkit cudnn ];

  makeFlags = [
    "CUDA_PATH=${cudatoolkit}"
    "SMS=${lib.replaceStrings [ ";" ] [" "] flags.cmakeCudaArchitecturesString}"
    # NOTE: CUDA_SEARCH_PATH is only ever used to find stubs.
    # Some packages (like deviceQueryDrv) try to link against driver stubs and are not built if they are not found.
    "CUDA_SEARCH_PATH=${cudatoolkit}/lib/stubs"
    "CUDNN_INCLUDE_PATH=${lib.getOutput "include" cudnn}/include"
    "CUDNN_LIB_PATH=${lib.getLib cudnn}/lib"
  ];

  enableParallelBuilding = true;

  # Sample directories which we won't build.
  ignoredSampleDirs = {
    # `mnistCUDNN` requires freeimage which is marked vulnerable in upstream as of 24.05
    mnistCUDNN = 1;
  };

  # In the case the sample directory doesn't match the name of the executable,
  # we can specify the name of the executable here.
  sampleExes = {
    "RNN_v8.0" = "RNN";
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
