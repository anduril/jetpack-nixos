let
  nsight_system_version = "2022.5.2";
in
{ lib,
  stdenv,
  runCommand,
  dpkg,
  makeWrapper,
  autoPatchelfHook,
  autoAddOpenGLRunpathHook,
  symlinkJoin,
  expat,
  pkg-config,
  substituteAll,
  gcc9,
  gcc10,
  l4t,
  zlib,
  qt6,
  xorg,
  fontconfig,
  dbus,
  nss,
  alsa-lib,
  xkeyboard_config,
  nspr,
  ncurses5,
  noto-fonts,
  buildFHSUserEnv,
  requireFile,
  nsightSystemSrcs ? (
    if stdenv.hostPlatform.system == "x86_64-linux" then requireFile rec {
        name = "NsightSystems-linux-public-2022.5.2.120-3231674.deb";
        sha256 = "011f1vxrmxnip02zmlsb224cc01nviva2070qadkwhmz409sjxag";
        message = ''
          For Jetpack 5.1, Nvidia doesn't upload the corresponding nsight system x86_64 version to the deb repo, so it need to be fetched using sdkmanager

          Once you have obtained the file, please use the following commands and re-run the installation:

          nix-prefetch-url file://path/to/${name}
        '';
      }
    else if stdenv.hostPlatform.system == "aarch64-linux" then debs.common."nsight-systems-${nsight_system_version}".src
    else throw "Unsupported architecture"),

  debs,
  cudaVersion,
}:

let
  # We should use gcc10 to match CUDA 11.4, but we get link errors on opencv and torch2trt if we do
  # ../../lib/libopencv_core.so.4.5.4: undefined reference to `__aarch64_ldadd4_acq_rel
  gccForCuda = gcc9;

  cudaVersionDashes = lib.replaceStrings [ "." ] [ "-"] cudaVersion;

  debsForSourcePackage = srcPackageName: lib.filter (pkg: (pkg.source or "") == srcPackageName) (builtins.attrValues debs.common);

  # TODO: Fix the pkg-config files
  buildFromDebs =
    { name, srcs, version ? debs.common.${name}.version,
      sourceRoot ? "source", buildInputs ? [], nativeBuildInputs ? [],
      postPatch ? "", postFixup ? "", autoPatchelf ? true, ...
    }@args:
    stdenv.mkDerivation ((lib.filterAttrs (n: v: !(builtins.elem n [ "name" "autoPatchelf" ])) args) // {
      pname = name;
      inherit version srcs;

      nativeBuildInputs = [ dpkg autoPatchelfHook autoAddOpenGLRunpathHook ] ++ nativeBuildInputs;
      buildInputs = [ stdenv.cc.cc.lib ] ++ buildInputs;

      unpackCmd = "for src in $srcs; do dpkg-deb -x $src source; done";

      dontConfigure = true;
      dontBuild = true;
      noDumpEnvVars = true;


      # In cross-compile scenarios, the directory containing `libgcc_s.so` and other such
      # libraries is actually under a target-specific directory such as
      # `${stdenv.cc.cc.lib}/aarch64-unknown-linux-gnu/lib/` rather than just plain `/lib` which
      # makes `autoPatchelfHook` fail at finding them libraries.
      postFixup = (lib.optionalString (stdenv.hostPlatform != stdenv.buildPlatform) ''
        addAutoPatchelfSearchPath ${stdenv.cc.cc.lib}/*/lib/
      '') + postFixup;

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

      meta = {
        platforms = [ "aarch64-linux" ];
      } // (args.meta or {});
    });

  # Combine all the debs that originated from the same source package and build
  # from that
  buildFromSourcePackage = { name, ...}@args: buildFromDebs ({
    inherit name;
    # Just using the first package for the version seems fine
    version = (lib.head (debsForSourcePackage name)).version;
    srcs = builtins.map (deb: deb.src) (debsForSourcePackage name);
  } // args);

  nsight_compute_version = "2022.2.1";
  cudaPackages = {
    cuda_cccl = buildFromSourcePackage { name = "cuda-thrust"; };
    cuda_cudart = buildFromSourcePackage {
      name = "cuda-cudart";
      preFixup = ''
        # Some build systems look for libcuda.so.1 expliticly:
        ln -s $out/lib/stubs/libcuda.so $out/lib/stubs/libcuda.so.1
      '';
    };
    cuda_cuobjdump = buildFromSourcePackage { name = "cuda-cuobjdump"; };
    cuda_cupti = buildFromSourcePackage { name = "cuda-cupti"; };
    cuda_cuxxfilt = buildFromSourcePackage { name = "cuda-cuxxfilt"; };
    cuda_documentation = buildFromSourcePackage { name = "cuda-documentation"; };
    cuda_gdb = buildFromSourcePackage { name = "cuda-gdb"; buildInputs = [ expat ]; };
    cuda_nvcc = buildFromSourcePackage {
      name = "cuda-nvcc";
      nativeBuildInputs = [ makeWrapper ];
      # Fixes from upstream nixpkgs cudatoolkit
      postFixup = ''
        # Set compiler for NVCC.
        wrapProgram $out/bin/nvcc \
          --prefix PATH : ${gccForCuda}/bin

        # Change the #error on recent GCC/Clang to a #warning
        sed -i $out/include/crt/host_config.h \
          -e 's/#error\(.*unsupported GNU version\)/#warning\1/' \
          -e 's/#error\(.*unsupported clang version\)/#warning\1/'
      '';
    };
    cuda_nvdisasm = buildFromSourcePackage { name = "cuda-nvdisasm"; };
    cuda_nvml_dev = buildFromSourcePackage { name = "cuda-nvml-dev"; };
    cuda_nvprune = buildFromSourcePackage { name = "cuda-nvprune"; };
    cuda_nvrtc = buildFromSourcePackage {
      name = "cuda-nvrtc";
      postFixup = ''
        # libnvrtc.so uses libnvrtc-builtins.so
        patchelf --add-rpath $out/lib $(readlink -f $out/lib/libnvrtc.so)
      '';
    };
    cuda_nvtx = buildFromSourcePackage { name = "cuda-nvtx"; };
    cuda_sanitizer_api = buildFromDebs {
      # There are 11-4 and 11-7 versions in the deb repo, and we only want one for now.
      name = "cuda-sanitizer-api";
      version = debs.common."cuda-sanitizer-${cudaVersionDashes}".version;
      srcs = [ debs.common."cuda-sanitizer-${cudaVersionDashes}".src ];
    };
    cuda_profiler_api = buildFromSourcePackage { name = "cuda-profiler-api"; };
    cudnn = buildFromSourcePackage {
      name = "cudnn";
      buildInputs = with cudaPackages; [ libcublas zlib ];
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
    libcudla = buildFromSourcePackage { name = "libcudla"; buildInputs = [ l4t.l4t-cuda ]; };
    nsight_compute_target = buildFromDebs {
      name = "nsight-compute-target";
      version = nsight_compute_version;
      srcs = debs.common."nsight-compute-${nsight_compute_version}".src;
      postPatch = ''
        # ncu relies on relative folder structure to find sections file so emulate that
        mkdir -p target
        cp -r "opt/nvidia/nsight-compute/${nsight_compute_version}/target/linux-v4l_l4t-t210-a64" target
        cp -r "opt/nvidia/nsight-compute/${nsight_compute_version}/extras" .
        cp -r "opt/nvidia/nsight-compute/${nsight_compute_version}/sections" .
        rm -rf opt usr

        # ncu requires that it remains under its original directory so symlink instead of copying
        # things out
        mkdir -p bin
        ln -sfv ../target/linux-v4l_l4t-t210-a64/ncu ./bin/ncu
      '';
      meta.platforms = [ "aarch64-linux" ];
    };
    nsight_compute_host = let
      nsight_out = buildFromDebs {
        name = "nsight-compute-host";
        version = nsight_compute_version;
        srcs = debs.common."nsight-compute-${nsight_compute_version}".src;
        dontAutoPatchelf = true;
        postPatch = 
        let
          mkPostPatch = arch : ''
            mkdir -p host
            cp -r "opt/nvidia/nsight-compute/${nsight_compute_version}/host/${arch}" host
            cp -r "opt/nvidia/nsight-compute/${nsight_compute_version}/extras" .
            cp -r "opt/nvidia/nsight-compute/${nsight_compute_version}/sections" .
            rm -r opt

            # ncu requires that it remains under its original directory so symlink instead of copying
            # things out
            mkdir -p bin
            ln -sfv ../host/${arch}/ncu-ui ./bin/ncu-ui
          '';
        in 
          if stdenv.hostPlatform.system == "x86_64-linux" then mkPostPatch "linux-desktop-glibc_2_11_3-x64"
          else if stdenv.hostPlatform.system == "aarch64-linux" then mkPostPatch "linux-v4l_l4t-t210-a64"
          else throw "Unsupported architecture";
        meta.platforms = [ "x86_64-linux" "aarch64-linux" ];
      };
    # ncu-ui has some hardcoded /usr access so use fhs instead of trying to patchelf
    # it also comes with its own qt6 .so, trying to use Nix qt6 libs results in weird
    # behavior(blank window) so just supply qt6 dependency instead of qt6 itself
    in buildFHSUserEnv {
      name = "ncu-ui";
      targetPkgs = pkgs: (
        [
          ncurses5
          xorg.libxcb
          fontconfig
          noto-fonts
          dbus
          nss
          xorg.libXcomposite
          xorg.libXdamage
          alsa-lib
          xorg.libXtst
          xorg.libSM
          xorg.libICE
          xorg.libXfixes
          xkeyboard_config
          expat
          nspr
        ] ++ qt6.qtbase.propagatedBuildInputs ++ qt6.qtwebengine.propagatedBuildInputs
      );
      runScript = ''
        ${nsight_out}/bin/ncu-ui $*
      '';
    };
    nsight_systems_target = buildFromDebs {
      name = "nsight-systems-target";
      version = nsight_system_version;
      srcs = debs.common."nsight-systems-${nsight_system_version}".src;
      postPatch = ''
        cp -r "opt/nvidia/nsight-systems/${nsight_system_version}/target-linux-tegra-armv8" .
        rm -rf opt

        # nsys requires that it remains under its original directory so symlink instead of copying
        # things out
        mkdir -p bin
        ln -sfv ../target-linux-tegra-armv8/nsys ./bin/nsys
        ln -sfv ../target-linux-tegra-armv8/nsys-launcher ./bin/nsys-launcher
      '';
      meta.platforms = [ "aarch64-linux" ];
    };
    nsight_systems_host = let
      nsight_out = buildFromDebs {
        name = "nsight-systems-host";
        srcs = nsightSystemSrcs;
        version = nsight_system_version;
        phases = [ "unpackPhase" "patchPhase" "installPhase" ];
        postPatch =
          let mkPostPatch = arch : ''
            mv opt/nvidia/nsight-systems/${nsight_system_version}/host-${arch} .
            rm -r opt

            mkdir -p bin
            # nsys requires that it remains under its original directory so symlink instead of copying
            # things out
            ln -sfv ../host-${arch}/nsys-ui ./bin/nsys-ui
          '';
          in
            if stdenv.hostPlatform.system == "x86_64-linux" then mkPostPatch "linux-x64"
            else if stdenv.hostPlatform.system == "aarch64-linux" then mkPostPatch "linux-armv8"
            else throw "Unsupported architecture";
        meta.platforms = [ "x86_64-linux" "aarch64-linux" ];
      };
    # nsys-ui has some hardcoded /usr access so use fhs instead of trying to patchelf
    # it also comes with its own qt6 .so, trying to use Nix qt6 libs results in weird
    # behavior(blank window) so just supply qt6 dependency instead of qt6 itself
    in buildFHSUserEnv {
      name = "nsys-ui";
      targetPkgs = pkgs: (
        [
          ncurses5
          xorg.libxcb
          fontconfig
          noto-fonts
          dbus
          nss
          xorg.libXcomposite
          xorg.libXdamage
          alsa-lib
          xorg.libXtst
          xorg.libSM
          xorg.libICE
          xorg.libXfixes
          xkeyboard_config
          expat
          nspr
        ] ++ qt6.qtbase.propagatedBuildInputs ++ qt6.qtwebengine.propagatedBuildInputs
      );
      runScript = ''
        ${nsight_out}/bin/nsys-ui $*
      '';
    };

    # Combined package. We construct it from the debs, since nvidia doesn't
    # distribute a combined cudatoolkit package for jetson
    cudatoolkit = (symlinkJoin {
      name = "cudatoolkit";
      version = cudaVersion;
      paths = with cudaPackages; [
        cuda_cccl cuda_cudart cuda_cuobjdump cuda_cupti cuda_cuxxfilt
        cuda_documentation cuda_gdb cuda_nvcc cuda_nvdisasm cuda_nvml_dev
        cuda_nvprune cuda_nvrtc cuda_nvtx cuda_sanitizer_api cuda_profiler_api libcublas
        libcufft libcurand libcusolver libcusparse libnpp
      ];
      # Bits from upstream nixpkgs cudatoolkit
      postBuild = ''
        # Ensure that cmake can find CUDA.
        mkdir -p $out/nix-support
        echo "cmakeFlags+=' -DCUDA_TOOLKIT_ROOT_DIR=$out'" >> $out/nix-support/setup-hook

        # Set the host compiler to be used by nvcc for CMake-based projects:
        # https://cmake.org/cmake/help/latest/module/FindCUDA.html#input-variables
        echo "cmakeFlags+=' -DCUDA_HOST_COMPILER=${gccForCuda}/bin'" >> $out/nix-support/setup-hook
      '';
    } // {
      cc = gccForCuda;
      majorMinorVersion = lib.versions.majorMinor cudaVersion;
      majorVersion = lib.versions.majorMinor cudaVersion;
    });

    ### Below are things that are not included in the cudatoolkit package

    # https://docs.nvidia.com/deploy/cuda-compatibility/index.html
    # TODO: This needs to be linked directly against driver libs
    # cuda-compat = buildFromSourcePackage { name = "cuda-compat"; };

    # Test with:
    # ./result/bin/trtexec --onnx=mnist.onnx
    # (mnist.onnx is from libnvinfer-samples deb)
    # TODO: This package is too large to want to just combine everything. Maybe split back into lib/dev/bin subpackages?
    tensorrt = let
      # Filter out samples. They're too big
      tensorrtDebs = builtins.filter (p: !(lib.hasInfix "libnvinfer-samples" p.filename)) (debsForSourcePackage "tensorrt");
    in buildFromDebs {
      name = "tensorrt";
      # Just using the first package for the version seems fine
      version = (lib.head tensorrtDebs).version;
      srcs = builtins.map (deb: deb.src) tensorrtDebs;

      buildInputs = (with cudaPackages; [ cuda_cudart libcublas libcudla cudnn ]) ++ (with l4t; [ l4t-core l4t-multimedia ]);
      # Remove unnecessary (and large) static libs
      postPatch = ''
        rm -rf lib/*.a

        mv src/tensorrt/bin bin
      '';

      # Tell autoPatchelf about runtime dependencies.
      # (postFixup phase is run before autoPatchelfHook.)
      postFixup = ''
        echo "Patching RPATH of libnvinfer libs"
        patchelf --debug --add-needed libnvinfer.so $out/lib/libnvinfer*.so.*
      '';
    };

    # vpi2
    vpi2 = buildFromDebs {
      name = "vpi2";
      version = debs.common.vpi2-dev.version;
      srcs = [ debs.common.libnvvpi2.src debs.common.vpi2-dev.src ];
      sourceRoot = "source/opt/nvidia/vpi2";
      buildInputs = (with l4t; [ l4t-core l4t-cuda l4t-nvsci l4t-3d-core l4t-multimedia l4t-pva ])
        ++ (with cudaPackages; [ libcufft libnpp ]);
      patches = [ ./vpi2.patch ];
      postPatch = ''
        rm -rf etc
        substituteInPlace lib/cmake/vpi/vpi-config.cmake --subst-var out
        substituteInPlace lib/cmake/vpi/vpi-config-release.cmake \
          --replace "lib/aarch64-linux-gnu" "lib/"
      '';
    };

    # Needed for vpi2-samples benchmark w/ pva to work
    vpi2-firmware = runCommand "vpi2-firmware" { nativeBuildInputs = [ dpkg ]; } ''
      dpkg-deb -x ${debs.common.libnvvpi2.src} source
      install -D source/opt/nvidia/vpi2/lib64/priv/vpi2_pva_auth_allowlist $out/lib/firmware/pva_auth_allowlist
    '';

    # TODO:
    #  libnvidia-container
  };
in cudaPackages
