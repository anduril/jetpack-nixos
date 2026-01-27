# This package is unfortunately not identical to the upstream cuda-samples
# published at https://github.com/NVIDIA/cuda-samples, so we can't use
# nixpkgs's pkgs/tests/cuda packages
{ autoAddDriverRunpath
, cuda_nvcc
, cudaMajorMinorVersion
, cudatoolkit
, dpkg
, flags
, lib
, nvidia-jetpack
, pkg-config
, stdenv
}:
let
  inherit (nvidia-jetpack) debs;
  inherit (stdenv.hostPlatform) parsed;

  cudaVersionDashes = lib.replaceStrings [ "." ] [ "-" ] cudaMajorMinorVersion;
in
stdenv.mkDerivation {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "cuda-samples";
  inherit (debs.common."cuda-samples-${cudaVersionDashes}") src version;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/usr/local/cuda-${cudaMajorMinorVersion}/samples";

  nativeBuildInputs = [ autoAddDriverRunpath cuda_nvcc dpkg pkg-config ];
  buildInputs = [ cudatoolkit ];

  # NOTE: ptxjit requires that we build for a single architecture, which we don't necessarily do.
  postPatch = ''
    substituteInPlace 0_Simple/matrixMul_nvrtc/Makefile \
      --replace-fail \
        '$(EXEC) cp "$(CUDA_PATH)/$(CUDA_INSTALL_TARGET_DIR)include/cooperative_groups.h" .' \
        '$(EXEC) cp "$(CUDA_PATH)/include/cooperative_groups.h" .' \
      --replace-fail \
        '$(EXEC) cp -r "$(CUDA_PATH)/$(CUDA_INSTALL_TARGET_DIR)include/cooperative_groups" .' \
        '$(EXEC) cp -r "$(CUDA_PATH)/include/cooperative_groups" .'

    substituteInPlace 6_Advanced/ptxjit/Makefile \
      --replace-fail \
        'SAMPLE_ENABLED := 1' \
        'SAMPLE_ENABLED := 0'
    
    nixLog "patching Makefiles with static libraries to link against dynamic libraries"
    for file in $(find . -type f -name Makefile); do
      if grep --quiet --fixed-strings "_static" "$file"; then
        substituteInPlace "$file" --replace-fail "_static" ""
      fi
    done
    unset -v file
  '';

  makeFlags = [
    "CUDA_PATH=${cudatoolkit}"
    "SMS=${lib.replaceStrings [ ";" ] [" "] flags.cmakeCudaArchitecturesString}"
    # NOTE: CUDA_SEARCH_PATH is only ever used to find stubs.
    # Some packages (like deviceQueryDrv) try to link against driver stubs and are not built if they are not found.
    "CUDA_SEARCH_PATH=${cudatoolkit}/lib/stubs"
  ];

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 -t $out/bin bin/${parsed.cpu.name}/${parsed.kernel.name}/release/*

    # *_nvrtc samples require your current working directory contains the corresponding .cu file
    find -ipath "*_nvrtc/*.cu" -exec install -Dt $out/data {} \;

    runHook postInstall
  '';
}
