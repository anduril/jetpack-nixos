# This package is unfortunately not identical to the upstream cuda-samples
# published at https://github.com/NVIDIA/cuda-samples, so we can't use
# nixpkgs's pkgs/tests/cuda packages
{ autoAddDriverRunpath
, cudaPackages
, debs
, dpkg
, lib
, pkg-config
, stdenv
, cmake
, fetchFromGitHub
}:
let
  inherit (cudaPackages)
    cuda_nvcc
    cudatoolkit
    cudaMajorMinorVersion
    cudaVersionDashes
    flags
    cuda_cccl
    cuda_cudart
    cuda_nvrtc
    cuda_nvtx
    cuda_profiler_api
    cudaAtLeast
    cudaOlder
    libcublas
    libcufft
    libcurand
    libcusolver
    libcusparse
    libnpp
    libnvjpeg
    ;
  inherit (stdenv.hostPlatform) parsed;
in
if cudaOlder "12" then
  stdenv.mkDerivation
  {
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
else
# Copied from https://github.com/ConnorBaker/cuda-packages/blob/7731ebdf397c5ce123571abf2dc41ebac86237d3/pkgs/development/cuda-modules/packages/cuda-samples.nix
  stdenv.mkDerivation (finalAttrs: {
    __structuredAttrs = true;
    strictDeps = true;

    pname = "cuda-samples";
    version = "12.8";

    # We should be able to use samples from the latest version of CUDA
    # on most of the CUDA package sets we have.
    # Plus, 12.8 and later are rewritten to use CMake which makes it much, much easier to build.
    src = fetchFromGitHub {
      owner = "NVIDIA";
      repo = "cuda-samples";
      tag = "v${finalAttrs.version}";
      hash = "sha256-Ba0Fi0v/sQ+1iJ4mslgyIAE+oK5KO0lMoTQCC91vpiA=";
    };

    prePatch =
      # https://github.com/NVIDIA/cuda-samples/issues/333
      ''
        echo "removing sample 0_Introduction/UnifiedMemoryStreams which requires OpenMP support for CUDA"
        substituteInPlace \
          "$NIX_BUILD_TOP/$sourceRoot/Samples/0_Introduction/CMakeLists.txt" \
          --replace-fail \
            'add_subdirectory(UnifiedMemoryStreams)' \
            '# add_subdirectory(UnifiedMemoryStreams)'
      ''
      # This sample tries to use a relative path, which doesn't work for our splayed installation.
      + ''
        echo "patching sample 0_Introduction/matrixMul_nvrtc"
        substituteInPlace \
          "$NIX_BUILD_TOP/$sourceRoot/Samples/0_Introduction/matrixMul_nvrtc/CMakeLists.txt" \
          --replace-fail \
            "\''${CUDAToolkit_BIN_DIR}/../include/cooperative_groups" \
            "${lib.getOutput "include" cuda_cudart}/include/cooperative_groups" \
          --replace-fail \
            "\''${CUDAToolkit_BIN_DIR}/../include/nv" \
            "${lib.getOutput "include" cuda_cccl}/include/nv" \
          --replace-fail \
            "\''${CUDAToolkit_BIN_DIR}/../include/cuda" \
            "${lib.getOutput "include" cuda_cccl}/include/cuda"
      ''
      # These three samples give undefined references, like
      # nvlink error   : Undefined reference to '__cudaCDP2Free' in 'CMakeFiles/cdpBezierTessellation.dir/BezierLineCDP.cu.o'
      # nvlink error   : Undefined reference to '__cudaCDP2Malloc' in 'CMakeFiles/cdpBezierTessellation.dir/BezierLineCDP.cu.o'
      # nvlink error   : Undefined reference to '__cudaCDP2GetParameterBufferV2' in 'CMakeFiles/cdpBezierTessellation.dir/BezierLineCDP.cu.o'
      # nvlink error   : Undefined reference to '__cudaCDP2LaunchDeviceV2' in 'CMakeFiles/cdpBezierTessellation.dir/BezierLineCDP.cu.o'
      + ''
        for sample in cdp{AdvancedQuicksort,BezierTessellation,Quadtree,SimplePrint,SimpleQuicksort}; do
          echo "removing sample 3_CUDA_Features/$sample which fails to link"
          substituteInPlace \
            "$NIX_BUILD_TOP/$sourceRoot/Samples/3_CUDA_Features/CMakeLists.txt" \
            --replace-fail \
              "add_subdirectory($sample)" \
              "# add_subdirectory($sample)"
        done
        unset -v sample
      ''
      + lib.optionalString (cudaOlder "12.4") ''
        echo "removing sample 3_CUDA_Features/graphConditionalNodes which requires at least CUDA 12.4"
        substituteInPlace \
          "$NIX_BUILD_TOP/$sourceRoot/Samples/3_CUDA_Features/CMakeLists.txt" \
          --replace-fail \
            "add_subdirectory(graphConditionalNodes)" \
            "# add_subdirectory(graphConditionalNodes)"
      ''
      # For some reason this sample requires a static library, which we don't propagate by default due to size.
      + ''
        echo "patching sample 4_CUDA_Libraries/simpleCUFFT_callback to use dynamic library"
        substituteInPlace \
          "$NIX_BUILD_TOP/$sourceRoot/Samples/4_CUDA_Libraries/simpleCUFFT_callback/CMakeLists.txt" \
          --replace-fail \
            'CUDA::cufft_static' \
            'CUDA::cufft'
      ''
      # Patch to use the correct path to libnvJitLink.so, or disable the sample if older than 12.4.
      + lib.optionalString (cudaOlder "12.4") ''
        echo "removing sample 4_CUDA_Libraries/jitLto which requires at least CUDA 12.4"
        substituteInPlace \
          "$NIX_BUILD_TOP/$sourceRoot/Samples/4_CUDA_Libraries/CMakeLists.txt" \
          --replace-fail \
            "add_subdirectory(jitLto)" \
            "# add_subdirectory(jitLto)"
      ''
      + lib.optionalString (cudaAtLeast "12.4") ''
        echo "patching sample 4_CUDA_Libraries/jitLto to use correct path to libnvJitLink.so"
        substituteInPlace \
          "$NIX_BUILD_TOP/$sourceRoot/Samples/4_CUDA_Libraries/jitLto/CMakeLists.txt" \
          --replace-fail \
            "\''${CUDAToolkit_LIBRARY_DIR}/libnvJitLink.so" \
            "${lib.getLib cudaPackages.libnvjitlink}/lib/libnvJitLink.so"
      ''
      # /build/NVIDIA-cuda-samples-v12.8/Samples/4_CUDA_Libraries/watershedSegmentationNPP/watershedSegmentationNPP.cpp:272:80: error: cannot convert 'size_t*' {aka 'long unsigned int*'} to 'int*'
      #   272 |         nppStatus = nppiSegmentWatershedGetBufferSize_8u_C1R(oSizeROI[nImage], &aSegmentationScratchBufferSize[nImage]);
      #       |                                                                                ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      #       |                                                                                |
      #       |                                                                                size_t* {aka long unsigned int*}
      + lib.optionalString (cudaOlder "12.8") ''
        echo "removing sample 4_CUDA_Libraries/watershedSegmentationNPP which requires at least CUDA 12.8"
        substituteInPlace \
          "$NIX_BUILD_TOP/$sourceRoot/Samples/4_CUDA_Libraries/CMakeLists.txt" \
          --replace-fail \
            "add_subdirectory(watershedSegmentationNPP)" \
            "# add_subdirectory(watershedSegmentationNPP)"
      ''
      # NVVM samples require a specific build of LLVM, which is a hassle.
      + ''
        echo "removing samples 7_libNVVM which require a specific build of LLVM"
        substituteInPlace \
          "$NIX_BUILD_TOP/$sourceRoot/Samples/CMakeLists.txt" \
          --replace-fail \
            'add_subdirectory(7_libNVVM)' \
            '# add_subdirectory(7_libNVVM)'
      ''
      # Don't use hard-coded CUDA architectures
      + ''
        echo "patching CMakeLists.txt to use provided CUDA architectures"
        local path=""
        while IFS= read -r -d $'\0' path; do
          echo "removing CMAKE_CUDA_ARCHITECTURES declaration from $path"
          substituteInPlace \
            "$path" \
            --replace-fail \
              'set(CMAKE_CUDA_ARCHITECTURES' \
              '# set(CMAKE_CUDA_ARCHITECTURES'
        done < <(grep --files-with-matches --null "set(CMAKE_CUDA_ARCHITECTURES" --recursive "$NIX_BUILD_TOP/$sourceRoot")
        unset -v path
      '';

    nativeBuildInputs = [
      # TODO(connorbaker): remove this if we want to support CUDA 12.8 or anything using cuda_compat
      autoAddDriverRunpath
      cmake
      cuda_nvcc
    ];

    buildInputs = [
      cuda_cccl
      cuda_cudart
      cuda_nvrtc
      cuda_nvtx
      cuda_profiler_api
      libcublas
      libcufft
      libcurand
      libcusolver
      libcusparse
      libnpp
      cudaPackages.libnvjitlink
      libnvjpeg
      (lib.getOutput "stubs" cuda_cudart)
    ];

    cmakeFlags = [
      (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" flags.cmakeCudaArchitecturesString)
      (lib.cmakeBool "BUILD_TEGRA" true)
    ];

    # TODO(@connorbaker):
    # For some reason, using the combined find command doesn't delete directories:
    # find "$PWD/Samples" \
    #     \( -type d -name CMakeFiles \) \
    #     -o \( -type f -name cmake_install.cmake \) \
    #     -o \( -type f -name Makefile \) \
    #     -exec rm -rf {} +
    installPhase = ''
      runHook preInstall

      pushd "$NIX_BUILD_TOP/$sourceRoot/''${cmakeBuildDir:?}" >/dev/null

      echo "deleting CMake related files"

      find "$PWD/Samples" -type d -name CMakeFiles -exec rm -rf {} +
      find "$PWD/Samples" -type f -name cmake_install.cmake -exec rm -rf {} +
      find "$PWD/Samples" -type f -name Makefile -exec rm -rf {} +

      echo "copying $PWD/Samples to $out/"
      mkdir -p "$out"
      cp -rv "$PWD/Samples"/* "$out/"

      popd >/dev/null

      runHook postInstall
    '';
  })

