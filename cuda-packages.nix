{ lib,
  stdenv,
  dpkg,
  autoPatchelfHook,
  autoAddOpenGLRunpathHook,
  symlinkJoin,
  expat,
  pkg-config,
  freeimage,
  prebuilt,

  debs,
  cudaVersion,
}:

let
  cudaVersionDashes = lib.replaceStrings [ "." ] [ "-"] cudaVersion;

  debsForSourcePackage = srcPackageName: lib.filter (pkg: (pkg.source or "") == srcPackageName) (builtins.attrValues debs.common);

  # TODO: Fix the pkg-config files
  buildFromDebs =
    { name, srcs, version ? debs.common.${name}.version,
      buildInputs ? [], nativeBuildInputs ? [],  postPatch ? "", postFixup ? "",
      autoPatchelf ? true, ...
    }@args:
    stdenv.mkDerivation ((lib.filterAttrs (n: v: !(builtins.elem n [ "name" "autoPatchelf" ])) args) // {
      pname = name;
      inherit version srcs;

      nativeBuildInputs = [ dpkg autoPatchelfHook autoAddOpenGLRunpathHook ] ++ nativeBuildInputs;
      buildInputs = [ stdenv.cc.cc.lib ] ++ buildInputs;

      unpackCmd = "for src in $srcs; do dpkg-deb -x $src ./; done";
      sourceRoot = ".";

      dontConfigure = true;
      dontBuild = true;
      noDumpEnvVars = true;

      postPatch = ''
        if [[ -d usr ]]; then
          cp -r usr/. .
          rm -rf usr
        fi

        if [[ -d local ]]; then
          cp -r local/. .
          rm -rf local
        fi

        if [[ -d cuda-${cudaVersion} ]]; then
          [[ -L cuda-${cudaVersion}/include ]] && rm -r cuda-${cudaVersion}/include
          [[ -L cuda-${cudaVersion}/lib64 ]] && rm -r cuda-${cudaVersion}/lib64 && ln -s lib lib64
          cp -r cuda-${cudaVersion}/. .
          rm -rf cuda-${cudaVersion}
        fi

        if [[ -d targets ]]; then
          cp -r targets/*/* .
          rm -rf targets
        fi

        if [[ -d etc ]]; then
          rm -rf etc/ld.so.conf.d
          rmdir --ignore-fail-on-non-empty etc
        fi

        if [[ -d include/aarch64-linux-gnu ]]; then
          cp -r include/aarch64-linux-gnu/. include/
          rm -rf include/aarch64-linux-gnu
        fi

        if [[ -d lib/aarch64-linux-gnu ]]; then
          cp -r lib/aarch64-linux-gnu/. lib/
          rm -rf lib/aarch64-linux-gnu
        fi

        rm -f lib/ld.so.conf

        ${postPatch}
      '';

      installPhase = ''
        cp -r . $out
      '';
    });

  # Combine all the debs that originated from the same source package and build
  # from that
  buildFromSourcePackage = { name, ...}@args: buildFromDebs ({
    inherit name;
    # Just using the first package for the version seems fine
    version = (lib.head (debsForSourcePackage name)).version;
    srcs = builtins.map (deb: deb.src) (debsForSourcePackage name);
  } // args);

  cudaPackages = {
    cuda_cccl = buildFromSourcePackage { name = "cuda-thrust"; };
    cuda_cudart = buildFromSourcePackage { name = "cuda-cudart"; };
    cuda_cuobjdump = buildFromSourcePackage { name = "cuda-cuobjdump"; };
    cuda_cupti = buildFromSourcePackage { name = "cuda-cupti"; };
    cuda_cuxxfilt = buildFromSourcePackage { name = "cuda-cuxxfilt"; };
    cuda_documentation = buildFromSourcePackage { name = "cuda-documentation"; };
    cuda_gdb = buildFromSourcePackage { name = "cuda-gdb"; buildInputs = [ expat ]; };
    cuda_nvcc = buildFromSourcePackage { name = "cuda-nvcc"; };
    cuda_nvdisasm = buildFromSourcePackage { name = "cuda-nvdisasm"; };
    cuda_nvml_dev = buildFromSourcePackage { name = "cuda-nvml-dev"; };
    cuda_nvprune = buildFromSourcePackage { name = "cuda-nvprune"; };
    cuda_nvrtc = buildFromSourcePackage { name = "cuda-nvrtc"; };
    cuda_nvtx = buildFromSourcePackage { name = "cuda-nvtx"; };
    cuda_sanitizer_api = buildFromDebs {
      # There are 11-4 and 11-7 versions in the deb repo, and we only want one for now.
      name = "cuda-sanitizer-api";
      version = debs.common."cuda-sanitizer-${cudaVersionDashes}".version;
      srcs = [ debs.common."cuda-sanitizer-${cudaVersionDashes}".src ];
    };
    cudnn = buildFromSourcePackage {
      name = "cudnn";
      buildInputs = with cudaPackages; [ libcublas ];
      # Unclear how it's supposed to work normally if all header files use
      # _v8.h suffix, since they refer to each other via #includes without any
      # suffix. Just symlink them all here
      postPatch = ''
        for filepath in $(find include/ -name '*_v8.h'); do
          ln -s $(basename $filepath) ''${filepath%_v8.h}.h
        done
      '';
      # Without --add-needed autoPatchelf forgets $ORIGIN
      postFixup = ''
        patchelf $out/lib/libcudnn.so --add-needed libcudnn_cnn_infer.so
      '';
    };
    libcublas = buildFromSourcePackage { name = "libcublas"; };
    libcufft = buildFromSourcePackage { name = "libcufft"; };
    libcurand = buildFromSourcePackage { name = "libcurand"; };
    libcusolver = buildFromSourcePackage { name = "libcusolver"; buildInputs = [ cudaPackages.libcublas ]; };
    libcusparse = buildFromSourcePackage { name = "libcusparse"; };
    libnpp = buildFromSourcePackage { name = "libnpp"; };
    #nsight_compute = buildFromSourcePackage { name = "nsight-compute"; };

    # Combined package. We construct it from the debs, since nvidia doesn't
    # distribute a combined cudatoolkit package for jetson
    cudatoolkit = symlinkJoin {
      name = "cudatoolkit";
      version = cudaVersion;
      paths = with cudaPackages; [
        cuda_cccl cuda_cudart cuda_cuobjdump cuda_cupti cuda_cuxxfilt
        cuda_documentation cuda_gdb cuda_nvcc cuda_nvdisasm cuda_nvml_dev
        cuda_nvprune cuda_nvrtc cuda_nvtx cuda_sanitizer_api libcublas
        libcufft libcurand libcusolver libcusparse libnpp
      ];
    };

    # https://docs.nvidia.com/deploy/cuda-compatibility/index.html
    # TODO: This needs to be linked directly against driver libs
    # cuda-compat = buildFromSourcePackage { name = "cuda-compat"; };

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

    # TODO: libnvinfer-samples
    # TODO: This package is too large to want to want to just combine. Maybe split back into lib/dev/bin subpackages?
    # Test with:
    # LD_LIBRARY_PATH=/run/opengl-driver/lib:/nix/store/q17hpgqcpyzskbpy8hp58pgmlz36hphy-l4t-nvidia-l4t-nvsci-35.1.0-20220825113828/lib /nix/store/jjn25fy0xj3y1swp22lb2v1fg4ldqvwr-tensorrt-8.4.1-1+cuda11.4/bin/trtexec --onnx=mnist.onnx
    tensorrt = let
      # Filter out samples. They're too big
      tensorrtDebs = builtins.filter (p: !(lib.hasInfix "libnvinfer-samples" p.filename)) (debsForSourcePackage "tensorrt");
    in buildFromDebs {
      name = "tensorrt";
      # Just using the first package for the version seems fine
      version = (lib.head tensorrtDebs).version;
      srcs = builtins.map (deb: deb.src) tensorrtDebs;

      buildInputs = (with cudaPackages; [ cuda_cudart libcublas cudnn ]) ++ (with prebuilt; [ l4t-core l4t-multimedia ]);
      # Remove unnecessary (and large) static libs
      postPatch = ''
        rm -rf lib/*.a

        mv src/tensorrt/bin bin
      '';

      # These libraries access each other at runtime
      # This is getting overwritten by autoPatchelfHook ?
      postFixup = ''
        patchelf --add-rpath $out/lib lib/lib*.so
      '';
    };
    #  tensorrt # Should probably get re-split into dev and non-dev components.
    #  tensorrt (8.4.1-1+cuda11.4)
    #  libnvidia-container
    #  libcudla
    #  cuda-profiler-api # Is this cuda_nvprof?
  };
in cudaPackages
