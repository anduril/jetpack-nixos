{ autoAddDriverRunpath
, cudaPackages
, debs
, dpkg
, stdenv
}:
# Contains a bunch of tests for tensorrt, for example:
# ./result/bin/sample_mnist --datadir=result/data/mnist
stdenv.mkDerivation {
  pname = "libnvinfer-samples";
  version = debs.common.libnvinfer-samples.version;
  src = debs.common.libnvinfer-samples.src;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/usr/src/tensorrt/samples";

  nativeBuildInputs = [ dpkg autoAddDriverRunpath ];
  buildInputs = with cudaPackages; [ tensorrt cuda_profiler_api cudnn ];

  # These environment variables are required by the /usr/src/tensorrt/samples/README.md
  CUDA_INSTALL_DIR = cudaPackages.cudatoolkit;
  CUDNN_INSTALL_DIR = cudaPackages.cudnn;

  enableParallelBuilding = true;

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
