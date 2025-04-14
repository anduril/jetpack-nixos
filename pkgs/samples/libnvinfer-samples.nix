{ autoAddDriverRunpath
, cudaPackages
, debs
, dpkg
, lib
, stdenv
}:
# Contains a bunch of tests for tensorrt, for example:
# ./result/bin/sample_mnist --datadir=result/data/mnist
let
  inherit (cudaPackages)
    cuda_cudart
    cuda_nvcc
    cuda_profiler_api
    cudatoolkit
    cudnn
    flags
    libcublas
    tensorrt
    ;
in
stdenv.mkDerivation {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "libnvinfer-samples";
  inherit (debs.common.libnvinfer-samples) src version;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/usr/src/tensorrt/samples";

  nativeBuildInputs = [ autoAddDriverRunpath cuda_nvcc dpkg ];
  buildInputs = [ cuda_cudart cuda_profiler_api cudnn libcublas tensorrt ];

  postPatch = ''
    substituteInPlace Makefile.config \
      --replace-fail \
        '-I"$(CUDNN_INSTALL_DIR)/include"' \
        '-I"${lib.getOutput "include" cudnn}/include"'
  '';

  enableParallelBuilding = true;

  makeFlags = [
    "CUDA_PATH=${cudatoolkit}"
    "SMS=${lib.replaceStrings [ ";" ] [" "] flags.cmakeCudaArchitecturesString}"
    # NOTE: CUDA_SEARCH_PATH is only ever used to find stubs.
    # Some packages (like deviceQueryDrv) try to link against driver stubs and are not built if they are not found.
    "CUDA_SEARCH_PATH=${cudatoolkit}/lib/stubs"
    "CUDA_INSTALL_DIR=${cudatoolkit}"
    "CUDNN_INSTALL_DIR=${cudnn}"
    "CUDNN_LIBDIR=${lib.getLib cudnn}/lib"
    "TRT_LIB_DIR=${lib.getLib tensorrt}/lib"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out

    rm -rf ../bin/chobj
    rm -rf ../bin/dchobj
    cp -r ../bin $out/
    cp -r ../data $out/

    runHook postInstall
  '';
}
