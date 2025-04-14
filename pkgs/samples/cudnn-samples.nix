{ autoAddDriverRunpath
, cudaPackages
, debs
, dpkg
, stdenv
}:
stdenv.mkDerivation {
  pname = "cudnn-samples";
  version = debs.common.libcudnn8-samples.version;
  src = debs.common.libcudnn8-samples.src;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/usr/src/cudnn_samples_v8";

  nativeBuildInputs = [ dpkg autoAddDriverRunpath ];
  buildInputs = with cudaPackages; [ cudatoolkit cudnn ];

  buildFlags = [
    "CUDA_PATH=${cudaPackages.cudatoolkit}"
    "CUDNN_INCLUDE_PATH=${cudaPackages.cudnn}/include"
    "CUDNN_LIB_PATH=${cudaPackages.cudnn}/lib"
  ];

  enableParallelBuilding = true;

  # Disabled mnistCUDNN since it requires freeimage which is marked vulnerable in upstream as of 24.05
  buildPhase = ''
    runHook preBuild

    for dirname in conv_sample multiHeadAttention RNN_v8.0; do
      pushd "$dirname"
      make $buildFlags
      popd 2>/dev/null
    done

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 -t $out/bin \
      conv_sample/conv_sample \
      multiHeadAttention/multiHeadAttention \
      RNN_v8.0/RNN

    runHook postInstall
  '';
}
