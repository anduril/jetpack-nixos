{ lib, system }:
finalCudaPackages: prevCudaPackages:
let
  inherit (lib)
    elem
    filter
    genAttrs
    getAttr
    hasAttr
    mapAttrs
    optionalString
    versions
    ;

  newCudaPackages =
    # The majority of our packages don't need any additional fixes -- upstream's package expressions work after
    # unpacking and normalizing the debians.
    genAttrs [
      "cuda_cudart"
      "cuda_cuobjdump"
      "cuda_cuxxfilt"
      "cuda_gdb"
      "cuda_nvcc"
      "cuda_nvdisasm"
      "cuda_nvml_dev"
      "cuda_nvprune"
      "cuda_nvrtc"
      "cuda_nvtx"
      "cuda_sanitizer_api"
      "libcublas"
      "libcufft"
      "libcurand"
      "libcusolver"
      "libcusparse"
      "libnpp"
    ]
      (name: finalCudaPackages.debWrapBuildRedist { drv = prevCudaPackages.${name}; })
    # Some of our packages need a bit more help: typically this involves additional normalization or including more dependencies.
    // {
      debWrapBuildRedist = import ./pkgs/cuda-packages-11-4/debWrapBuildRedist.nix {
        inherit (finalCudaPackages) cudaMajorMinorVersion normalizeDebs;
        inherit (finalCudaPackages.pkgs) lib nvidia-jetpack;
      };

      cuda-samples = finalCudaPackages.callPackage ./pkgs/cuda-packages-11-4/cuda-samples.nix { };

      nsight_compute_host = finalCudaPackages.callPackage ./pkgs/cuda-packages-11-4/nsight_compute_host.nix { };

      nsight_compute_target = finalCudaPackages.callPackage ./pkgs/cuda-packages-11-4/nsight_compute_target.nix { };

      nsight_systems_host = finalCudaPackages.callPackage ./pkgs/cuda-packages-11-4/nsight_systems_host.nix { };

      nsight_systems_target = finalCudaPackages.callPackage ./pkgs/cuda-packages-11-4/nsight_systems_target.nix { };

      cuda_cupti = finalCudaPackages.debWrapBuildRedist {
        drv = prevCudaPackages.cuda_cupti;
        postDebNormalization = ''
          pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null
          mv \
            --verbose \
            --no-clobber \
            --target-directory "$PWD" \
            "$PWD/extras/CUPTI/samples"
          echo "removing $PWD/extras"
          rm --recursive --dir "$PWD/extras" || {
            nixErrorLog "$PWD/extras contains non-empty directories: $(ls -laR "$PWD/extras")"
            exit 1
          }
          popd >/dev/null
        '';
      };

      cudnn = finalCudaPackages.debWrapBuildRedist {
        drv = prevCudaPackages.cudnn;
        extension = finalAttrs: prevAttrs: {
          postFixup =
            let
              cudnnMajorVersion = versions.major finalAttrs.version;
            in
            # TODO(@connorbaker): Is this still necessary?
            prevAttrs.postFixup or ""
            + ''
              nixLog "creating symlinks for header files in include without the _v${cudnnMajorVersion} suffix before the file extension"
              pushd "''${!outputInclude:?}/include" >/dev/null
              for file in *.h; do
                nixLog "symlinking $file to $(basename "$file" "_v${cudnnMajorVersion}.h").h"
                ln -s "$file" "$(basename "$file" "_v${cudnnMajorVersion}.h").h"
              done
              unset -v file
              popd >/dev/null
            '';
        };
      };

      libcudla = finalCudaPackages.debWrapBuildRedist {
        drv = prevCudaPackages.libcudla;
        extension = prevAttrs: {
          # There's no stubs available in the Debian installer.
          outputs = filter (output: output != "stubs") prevAttrs.outputs;

          # Inject the driver libraries needed for libcudla's DLA functionality so transitive symbol resolution in consumers
          # of libcudla don't fail.
          # NOTE: This is the same pattern of adding driver libraries as described in pkgs/cuda-extensions/default.nix.
          buildInputs = prevAttrs.buildInputs or [ ] ++ [
            finalCudaPackages.pkgs.nvidia-jetpack.l4t-core # libnvdla_runtime.so
          ];

          # Since we're explicitly including the library, we want autoPatchelf to fail if it can't find it.
          autoPatchelfIgnoreMissingDeps = lib.filter
            (
              name: name != "libnvdla_runtime.so"
            ) prevAttrs.autoPatchelfIgnoreMissingDeps or [ ];
        };
      };

      # NOTE: TensorRT's 8.x series is only available as debian installers. Vendor them here for x86_64-linux.
      tensorrt =
        let
          fetchTensorRTDeb =
            { version, variant, baseURL }:
            packageName: sha256:
            let
              suffix = (if packageName == "libnvinfer-samples" then "all" else "amd64") + ".deb";
            in
            finalCudaPackages.pkgs.fetchurl {
              inherit sha256;
              url = "${baseURL}/${packageName}_${version}-1+${variant}_${suffix}";
            };

          x86_64-linux-release = {
            version = "8.5.2";

            # Hashes are taken from:
            # https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/Packages
            debs = {
              variant = "cuda11.8";
              baseURL = "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64";
              hashes = {
                libnvinfer-bin = "73cd5543855ff75b6248f367db6d4b6da1375da106138f2da9bca947fa6b53dc";
                libnvinfer-dev = "f773240884fd10ec9017d522e460b2c7544757b4509ad88467b37b0ff1a0aa3d";
                libnvinfer-plugin-dev = "821db031ddd371a0c752b9e67f098c0e0328e0bbae73e27a2c87acdcb55ebfbf";
                libnvinfer-plugin8 = "157913b7be8773d3357cd4cce19b182f4edcec039bdc0e9789044fa10b0557cc";
                libnvinfer-samples = "51571904329ee412942b5c9a10f97040c2a98e026af8f3d22902472b11f0646e";
                libnvinfer8 = "f6f9b2c4a0e525245f9fcb663d7ce278fbc68f139ffb229f33fe9f7639ba9ed0";
                libnvonnxparsers-dev = "7e1397e200d01fc3dda62aae513e5a561da1bb8392fb7b3a083de6bd66b4a9aa";
                libnvonnxparsers8 = "5f0bd8c523f2b880382446a73e66a5c3cf35270a6bfb97a10e00d49d03da5ccc";
                libnvparsers-dev = "a193d525250c3b84c739a2bc9e764d23231e57b8672eda145f27f5805d05737b";
                libnvparsers8 = "e25ed8290064ab79acdc2da5a71f83fc3f1ce8a76934e36f0186eb1c7e1ba2bb";
              };
            };
          };
        in
        finalCudaPackages.debWrapBuildRedist {
          drv = prevCudaPackages.tensorrt;
          postDebNormalization = ''
            pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null
            mv --verbose --no-clobber "$PWD/src/tensorrt" "$PWD/samples"
            nixLog "removing $PWD/src"
            rm --recursive --dir "$PWD/src" || {
              nixErrorLog "$PWD/src contains non-empty directories: $(ls -laR "$PWD/src")"
              exit 1
            }

            nixLog "moving trtexec to top-level bin directory"
            mv --verbose --no-clobber "$PWD/samples/bin" "$PWD/bin"

            nixLog "creating fake python wheel for buildRedist to remove"
            mkdir -p "$PWD/python"
            touch "$PWD/python/DELETE_ME.whl"

            nixLog "creating fake stubs directory for buildRedist to remove"
            mkdir -p "$PWD/lib/stubs"

            popd >/dev/null
          '';
          extension = prevAttrs: {
            src =
              if system == "x86_64-linux" then
                prevAttrs.src.override
                  {
                    pname = "tensorrt-debs";
                    inherit (x86_64-linux-release) version;
                    srcs = lib.mapAttrsToList
                      (fetchTensorRTDeb {
                        inherit (x86_64-linux-release) version;
                        inherit (x86_64-linux-release.debs) baseURL variant;
                      })
                      x86_64-linux-release.debs.hashes;
                  }
              else prevAttrs.src;

            version =
              if system == "x86_64-linux" then
                x86_64-linux-release.version
              else
                prevAttrs.version;

            buildInputs = prevAttrs.buildInputs ++ [
              finalCudaPackages.cuda_nvrtc # libnvrtc.so and libnvrtc-builtins.so
              finalCudaPackages.cudnn # libcublas.so.11 and libcublasLt.so.11
              finalCudaPackages.libcublas # libcudnn.so.8
            ];

            postFixup =
              prevAttrs.prevAttrs or ""
              + ''
                nixLog "patchelf-ing ''${!outputLib:?}/lib/libnvinfer.so with runtime dependencies"
                patchelf \
                  "''${!outputLib:?}/lib/libnvinfer.so" \
                  --add-needed libnvrtc.so \
                  --add-needed libnvrtc-builtins.so
              '';

            passthru = prevAttrs.passthru // {
              # Doesn't come from a release manifest.
              release = null;
              # Only Jetson devices (pre-Thor) and x86_64-linux are supported.
              supportedNixSystems = [ "aarch64-linux" "x86_64-linux" ];
              supportedRedistSystems = [ "linux-aarch64" "linux-x86_64" ];
            };
          };
        };

      tensorrt-samples = prevCudaPackages.tensorrt-samples.overrideAttrs (finalAttrs: prevAttrs: {
        src =
          let
            # We offer an x86_64-linux version so we can test TensorRT (which we also offer for x86_64-linux).
            tensorrt-samples-source =
              if system == "x86_64-linux" then
                {
                  src = finalCudaPackages.pkgs.fetchurl {
                    sha256 = "sha256-UVcZBDKe5BKUK1yaEPlwQMKpjgJq+PPSKQJHKxHwZG4=";
                    url = "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/libnvinfer-samples_8.5.2-1+cuda11.8_all.deb";
                  };
                  version = "8.5.2-1+cuda11.8";
                }
              else
                finalCudaPackages.pkgs.nvidia-jetpack.debs.common.libnvinfer-samples;
          in
          finalCudaPackages.pkgs.stdenvNoCC.mkDerivation {
            __structuredAttrs = true;
            strictDeps = true;
            inherit (tensorrt-samples-source) version;
            pname = "tensorrt-samples-source-debs";
            srcs = [ tensorrt-samples-source.src ];
            nativeBuildInputs = [ finalCudaPackages.pkgs.dpkg ];
            outputs = [ "out" "data" ];
            phases = [
              "unpackPhase"
              "patchPhase"
              "installPhase"
            ];
            sourceRoot = "source";
            unpackPhase = ''
              runHook preUnpack

              for src in "''${srcs[@]}"; do
                nixLog "unpacking debian archive $src to $sourceRoot"
                dpkg-deb -x "$src" "$sourceRoot"
              done
              unset -v src

              runHook postUnpack
            '';
            installPhase = ''
              runHook preInstall

              mkdir -p "$data"
              mv --verbose usr/src/tensorrt/data/* "$data"
              mkdir -p "$out"
              mv --verbose usr/src/tensorrt/samples/* "$out"

              runHook postInstall
            '';
          };

        # Wipe the cmakeFlags
        cmakeFlags = [ ];

        # Wipe the postPatch phase for upstream which was created for CMake.
        postPatch = ''
          substituteInPlace Makefile.config \
            --replace-fail \
              '-I"$(CUDNN_INSTALL_DIR)/include"' \
              '-I"${lib.getOutput "include" finalCudaPackages.cudnn}/include"'
        '';

        enableParallelBuilding = true;

        env = prevAttrs.env or { } // {
          LDFLAGS = toString [
            # Fake libcuda.so (the real one is deployed impurely)
            "-L${lib.getOutput "stubs" finalCudaPackages.cuda_cudart}/lib/stubs"
          ];
        };

        # Wipe the existing dependencies, which include cmake
        nativeBuildInputs = [ finalCudaPackages.cuda_nvcc ];

        # Add more packages we require
        buildInputs = prevAttrs.buildInputs or [ ] ++ [
          finalCudaPackages.libcublas
          finalCudaPackages.cudnn
        ] ++ lib.optionals finalCudaPackages.libcudla.meta.available [
          finalCudaPackages.libcudla
        ];

        buildFlags = [
          "SMS=${lib.replaceStrings [ ";" ] [" "] finalCudaPackages.flags.cmakeCudaArchitecturesString}"
          "CUDA_INSTALL_DIR=${finalCudaPackages.cudatoolkit}"
          "CUDNN_INSTALL_DIR=${finalCudaPackages.cudnn}"
          "CUDNN_LIBDIR=${lib.getLib finalCudaPackages.cudnn}/lib"
          "TRT_LIB_DIR=${lib.getLib finalCudaPackages.tensorrt}/lib"
        ] ++ lib.optionals (system == "aarch64-linux") [
          "L4T_BUILD=1"
          "ENABLE_DLA=1"
        ];

        installPhase = ''
          runHook preInstall

          mkdir -p "$out"
          rm -rf ../bin/chobj ../bin/dchobj ../bin/*_debug
          mv --verbose ../bin "$out"/

          runHook postInstall
        '';

        passthru = prevAttrs.passthru // {
          sample-data = finalAttrs.src.data;

          # Introduce testers unique to our source.
          testers = prevAttrs.passthru.testers // lib.optionalAttrs finalCudaPackages.libcudla.meta.available {
            # Not present upstream, no risk of clobbering.
            sample_cudla.default = finalAttrs.passthru.mkTester "sample_cudla" [ "sample_cudla" ];
          };
        };
      });

      cuda_cccl = finalCudaPackages.debWrapBuildRedist {
        sourceName = "cuda-thrust";
        drv = prevCudaPackages.cuda_cccl;
      };

      # NOTE: CUDA 11.4 doesn't provide cuda-profiler-api for x86_64-linux, so we repackage the debian for it.
      cuda_profiler_api = finalCudaPackages.debWrapBuildRedist {
        drv = prevCudaPackages.cuda_profiler_api;
        # Need additional normalization because the CUDA version is different from the one used in the package set.
        postDebNormalization = optionalString (system == "x86_64-linux") ''
          pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null
          mv \
            --verbose \
            --no-clobber \
            --target-directory "$PWD" \
            "$PWD/local/cuda-11.8/targets/x86_64-linux/include"

          nixLog "removing $PWD/local"
          rm --recursive --dir "$PWD/local" || {
            nixErrorLog "$PWD/local contains non-empty directories: $(ls -laR "$PWD/local")"
            exit 1
          }
          popd >/dev/null
        '';
        extension = prevAttrs: {
          src =
            if system == "x86_64-linux" then
              prevAttrs.src.override
                {
                  pname = "cuda-profiler-api-11-8-debs";
                  version = "11.8.86";
                  srcs = [
                    (finalCudaPackages.pkgs.fetchurl {
                      sha256 = "755ed6c2583cb70d96d57b84082621f87f9339573b973da91faeacba60ecfeeb";
                      url = "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-profiler-api-11-8_11.8.86-1_amd64.deb";
                    })
                  ];
                }
            else prevAttrs.src;

          version =
            if system == "x86_64-linux" then
              "11.8.86"
            else
              prevAttrs.version;

          passthru = prevAttrs.passthru // {
            # Doesn't come from a release manifest.
            release = null;
            # Only Jetson devices (pre-Thor) and x86_64-linux are supported.
            supportedNixSystems = [ "aarch64-linux" "x86_64-linux" ];
            supportedRedistSystems = [ "linux-aarch64" "linux-x86_64" ];
          };
        };
      };

      # cuda_nvprof is expected to exist for CUDA versions prior to 11.8.
      # However, JetPack NixOS provides cuda_profiler_api, so just include a reference to that.
      # https://github.com/NixOS/nixpkgs/blob/9cb344e96d5b6918e94e1bca2d9f3ea1e9615545/pkgs/development/python-modules/torch/source/default.nix#L543-L545
      cuda_nvprof = finalCudaPackages.cuda_profiler_api;

      # Set to null to avoid using cuda_compat; since this is for CUDA 11.4, which JetPack 5 released with,
      # there is no cuda_compat available.
      cuda_compat = null;

      nsight_compute = prevCudaPackages.nsight_compute.overrideAttrs (prevAttrs: {
        pname = "nsight_compute-unsupported-on-jetson-use-nsight_compute_host";
        meta = prevAttrs.meta // {
          broken = true;
        };
      });

      nsight_systems = prevCudaPackages.nsight_systems.overrideAttrs (prevAttrs: {
        pname = "nsight_systems-unsupported-on-jetson-use-nsight_systems_host";
        meta = prevAttrs.meta // {
          broken = true;
        };
      });
    };

  canUseOurPackageVersion = finalCudaPackages.cudaMajorMinorVersion == "11.4";
  canUseOurPackagePlatform = finalCudaPackages.backendStdenv.hostRedistSystem == "linux-aarch64";
in
mapAttrs
  (name: value:
  # To make the extension safe to use, we add new attributes, but pass through all the existing attributes if we are not on the correct system.
  # The exceptions to this are cuda_profiler_api, TensorRT, and tensorrt-samples, which we also provide, since we package it for both Jetson and x86_64-linux.
  if !hasAttr name prevCudaPackages || (canUseOurPackageVersion && (elem name [ "cuda_profiler_api" "tensorrt" "tensorrt-samples" ] || canUseOurPackagePlatform)) then
    value
  else
    getAttr name prevCudaPackages
  )
  newCudaPackages
