{ stdenv, lib, fetchurl, dpkg, pkg-config, autoAddOpenGLRunpathHook, freeimage,
  cmake, opencv, opencv2, libX11, libdrm, libv4l, libglvnd, python2,

  prebuilt, cudaPackages,
  cudaVersion, debs
}:
let
  cudaVersionDashes = lib.replaceStrings [ "." ] [ "-"] cudaVersion;

  # This package is unfortunately not identical to the upstream cuda-samples
  # published at https://github.com/NVIDIA/cuda-samples, so we can't use
  # nixpkgs's pkgs/tests/cuda packages
  cuda-samples = stdenv.mkDerivation {
    pname = "cuda-samples";
    version = debs.common."cuda-samples-${cudaVersionDashes}".version;
    src = debs.common."cuda-samples-${cudaVersionDashes}".src;

    unpackCmd = "dpkg -x $src source";
    sourceRoot = "source/usr/local/cuda-${cudaVersion}/samples";

    nativeBuildInputs = [ dpkg pkg-config autoAddOpenGLRunpathHook ];
    buildInputs = [ cudaPackages.cudatoolkit ];

    preConfigure = ''
      export CUDA_PATH=${cudaPackages.cudatoolkit}
    '';

    enableParallelBuilding = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 -t $out/bin bin/${stdenv.hostPlatform.parsed.cpu.name}/${stdenv.hostPlatform.parsed.kernel.name}/release/*

      runHook postInstall
    '';
  };

  cudnn-samples = stdenv.mkDerivation {
    pname = "cudnn-samples";
    version = debs.common.libcudnn8-samples.version;
    src = debs.common.libcudnn8-samples.src;

    unpackCmd = "dpkg -x $src source";
    sourceRoot = "source/usr/src/cudnn_samples_v8";

    nativeBuildInputs = [ dpkg autoAddOpenGLRunpathHook ];
    buildInputs = with cudaPackages; [ cudatoolkit cudnn freeimage ];

    buildFlags = [
      "CUDA_PATH=${cudaPackages.cudatoolkit}"
      "CUDNN_INCLUDE_PATH=${cudaPackages.cudnn}/include"
      "CUDNN_LIB_PATH=${cudaPackages.cudnn}/lib"
    ];

    enableParallelBuilding = true;

    buildPhase = ''
      runHook preBuild

      pushd conv_sample
      make $buildFlags
      popd 2>/dev/null

      pushd mnistCUDNN
      make $buildFlags
      popd 2>/dev/null

      pushd multiHeadAttention
      make $buildFlags
      popd 2>/dev/null

      pushd RNN_v8.0
      make $buildFlags
      popd 2>/dev/null

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 -t $out/bin \
        conv_sample/conv_sample \
        mnistCUDNN/mnistCUDNN \
        multiHeadAttention/multiHeadAttention \
        RNN_v8.0/RNN

      runHook postInstall
    '';
  };

  # Contains a bunch of tests for tensorrt, for example:
  # ./result/bin/sample_mnist --datadir=result/data/mnist
  libnvinfer-samples = stdenv.mkDerivation {
    pname = "libnvinfer-samples";
    version = debs.common.libnvinfer-samples.version;
    src = debs.common.libnvinfer-samples.src;

    unpackCmd = "dpkg -x $src source";
    sourceRoot = "source/usr/src/tensorrt/samples";

    nativeBuildInputs = [ dpkg autoAddOpenGLRunpathHook ];
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
  };

  # https://docs.nvidia.com/jetson/l4t-multimedia/group__l4t__mm__test__group.html
  multimedia-samples = stdenv.mkDerivation {
    pname = "multimedia-samples";
    src = debs.common.nvidia-l4t-jetson-multimedia-api.src;
    version = debs.common.nvidia-l4t-jetson-multimedia-api.version;

    unpackCmd = "dpkg -x $src source";
    sourceRoot = "source/usr/src/jetson_multimedia_api";

    nativeBuildInputs = [ dpkg python2 ];
    buildInputs = [ libX11 libdrm  libglvnd opencv2 libv4l ] # TODO: nixpkgs libv4l is very likely incompatible. We need to use the prebuilt one or see what OE4T does.
      ++ (with prebuilt; [ l4t-cuda l4t-multimedia l4t-camera ])
      ++ (with cudaPackages; [ cudatoolkit tensorrt ]);

    # Usually provided by pkg-config, but the samples don't use it.
    NIX_CFLAGS_COMPILE = [ "-I${lib.getDev libdrm}/include/libdrm" ];

    # TODO: Unify this with headers in l4t-jetson-multimedia-api
    patches = [
      (fetchurl {
        url = "https://raw.githubusercontent.com/OE4T/meta-tegra/af0a93313c13e9eac4e80082d8a8e8ac5f7ad6e8/recipes-multimedia/argus/files/0005-Remove-DO-NOT-USE-declarations-from-v4l2_nv_extensio.patch";
        sha256 = "sha256-IJ1teGEUxYDEPYSvYZbqdmUYg9tOORN7WGYpDaUUnHY=";
      })
    ];

    postPatch = ''
      substituteInPlace samples/Rules.mk \
        --replace /usr/local/cuda "${cudaPackages.cudatoolkit}"

      substituteInPlace samples/08_video_dec_drm/Makefile \
        --replace /usr/bin/python "${python2}/bin/python"
    '';

    installPhase = ''
      runHook preInstall

      install -Dm 755 -t $out/bin $(find samples -type f -perm 755)
      rm -f $out/bin/*.h

      cp -r data $out/

      runHook postInstall
    '';
  };

  # Tested via "./result/bin/vpi_sample_05_benchmark <cpu|pva|cuda>" (Try pva especially)
  # Getting a bunch of "pva 16000000.pva0: failed to get firmware" messages, so unsure if its working.
  vpi2-samples = stdenv.mkDerivation {
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
  };
in {
  inherit
    cuda-samples
    cudnn-samples
    libnvinfer-samples
    multimedia-samples
    vpi2-samples;
}
