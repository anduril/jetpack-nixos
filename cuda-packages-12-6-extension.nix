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
    optionalAttrs
    versions
    ;

  debWrapBuildRedist = import ./pkgs/cuda-packages-11-4/debWrapBuildRedist.nix {
    inherit (finalCudaPackages) cudaMajorMinorVersion normalizeDebs;
    inherit (finalCudaPackages.pkgs) lib nvidia-jetpack;
  };

  wrap = debWrapBuildRedist;

  # Packages torch / ctranslate2 expect from cudaPackages on JetPack 6.
  debWrappedNames = filter (name: hasAttr name prevCudaPackages) [
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
    "libnvjitlink"
    "libcufile"
  ];

  newCudaPackages =
    genAttrs debWrappedNames (name: wrap { drv = prevCudaPackages.${name}; })
    // {
      inherit debWrapBuildRedist;
    }
    // optionalAttrs (hasAttr "cuda_cupti" prevCudaPackages) {
      cuda_cupti = wrap {
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
    }
    // optionalAttrs (hasAttr "cudnn" prevCudaPackages) {
      cudnn = wrap {
        drv = prevCudaPackages.cudnn;
        extension = finalAttrs: prevAttrs: {
          postFixup =
            let
              cudnnMajorVersion = versions.major finalAttrs.version;
            in
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
    }
    // optionalAttrs (hasAttr "tensorrt" prevCudaPackages) {
      tensorrt = wrap {
        drv = prevCudaPackages.tensorrt;
        postDebNormalization = ''
          pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null
          if [[ -d "$PWD/src/tensorrt" ]]; then
            mv --verbose --no-clobber "$PWD/src/tensorrt" "$PWD/samples"
            nixLog "removing $PWD/src"
            rm --recursive --dir "$PWD/src" || {
              nixErrorLog "$PWD/src contains non-empty directories: $(ls -laR "$PWD/src")"
              exit 1
            }
          fi
          if [[ -d "$PWD/samples/bin" ]]; then
            nixLog "moving trtexec to top-level bin directory"
            mkdir -p "$PWD/bin"
            mv --verbose --no-clobber "$PWD/samples/bin"/* "$PWD/bin/" || true
          fi
          mkdir -p "$PWD/python"
          touch "$PWD/python/DELETE_ME.whl"
          mkdir -p "$PWD/lib/stubs"
          popd >/dev/null
        '';
        extension = finalAttrs: prevAttrs: {
          buildInputs = (prevAttrs.buildInputs or [ ]) ++ [
            finalCudaPackages.cuda_nvrtc
            finalCudaPackages.cudnn
            finalCudaPackages.libcublas
          ];
          passthru = prevAttrs.passthru // {
            release = null;
            supportedNixSystems = [ "aarch64-linux" ];
            supportedRedistSystems = [ "linux-aarch64" ];
          };
        };
      };
    }
    // optionalAttrs (hasAttr "cuda_cccl" prevCudaPackages) {
      cuda_cccl = wrap {
        sourceName = "cuda-cccl";
        drv = prevCudaPackages.cuda_cccl;
      };
    }
    // optionalAttrs (hasAttr "cuda_compat" prevCudaPackages && prevCudaPackages.cuda_compat != null) {
      cuda_compat = wrap {
        sourceName = "cuda-compat";
        drv = prevCudaPackages.cuda_compat;
      };
    }
    // optionalAttrs (hasAttr "libcudla" prevCudaPackages) {
      libcudla = wrap {
        drv = prevCudaPackages.libcudla;
        extension = prevAttrs: {
          outputs = filter (output: output != "stubs") prevAttrs.outputs;
          buildInputs = prevAttrs.buildInputs or [ ] ++ [
            finalCudaPackages.pkgs.nvidia-jetpack.l4t-core
          ];
          autoPatchelfIgnoreMissingDeps = lib.filter
            (name: name != "libnvdla_runtime.so")
            (prevAttrs.autoPatchelfIgnoreMissingDeps or [ ]);
        };
      };
    };

  canUseOurPackageVersion = finalCudaPackages.cudaMajorMinorVersion == "12.6";
  canUseOurPackagePlatform = finalCudaPackages.backendStdenv.hostRedistSystem == "linux-aarch64";
in
mapAttrs
  (name: value:
  if
    !hasAttr name prevCudaPackages
    || (canUseOurPackageVersion && (elem name [ "tensorrt" ] || canUseOurPackagePlatform))
  then
    value
  else
    getAttr name prevCudaPackages
  )
  newCudaPackages
