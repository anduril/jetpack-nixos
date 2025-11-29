{ lib }:
finalCudaPackages: prevCudaPackages:
let
  inherit (lib)
    filter
    genAttrs
    optionalAttrs
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
      "cuda_profiler_api"
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

      normalizeDebs = import ./pkgs/cuda-packages-11-4/normalizeDebs.nix {
        inherit (finalCudaPackages) cudaMajorMinorVersion;
        inherit (finalCudaPackages.pkgs) dpkg lib srcOnly stdenvNoCC;
      };

      cuda-samples = finalCudaPackages.callPackage ./pkgs/cuda-packages-11-4/cuda-samples.nix { };

      nsight_compute_host = finalCudaPackages.callPackage ./pkgs/cuda-packages-11-4/nsight_compute_host.nix { };

      nsight_compute_target = finalCudaPackages.callPackage ./pkgs/cuda-packages-11-4/nsight_compute_target.nix { };

      nsight_systems_host = finalCudaPackages.callPackage ./pkgs/cuda-packages-11-4/nsight_systems_host.nix { };

      nsight_systems_target = finalCudaPackages.callPackage ./pkgs/cuda-packages-11-4/nsight_systems_target.nix { };

      cuda_cupti = finalCudaPackages.debWrapBuildRedist {
        drv = prevCudaPackages.cuda_cupti;
        extraDebNormalization = ''
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

      tensorrt = finalCudaPackages.debWrapBuildRedist {
        drv = prevCudaPackages.tensorrt;
        extraDebNormalization = ''
          pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null
          mv --verbose --no-clobber "$PWD/src/tensorrt" "$PWD/samples"
          nixLog "removing $PWD/src"
          rm --recursive --dir "$PWD/src" || {
            nixErrorLog "$PWD/src contains non-empty directories: $(ls -laR "$PWD/extras")"
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
        };
      };

      cuda_cccl = finalCudaPackages.debWrapBuildRedist {
        sourceName = "cuda-thrust";
        drv = prevCudaPackages.cuda_cccl;
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
in
optionalAttrs (prevCudaPackages.cudaMajorMinorVersion == "11.4") newCudaPackages
