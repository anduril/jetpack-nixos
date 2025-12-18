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
          buildInputs = [
            finalCudaPackages.pkgs.nvidia-jetpack.l4t-core # libnvdla_compiler.so and libnvdla_runtime.so
            finalCudaPackages.pkgs.nvidia-jetpack.l4t-cuda # libcuda.so.1
          ];
        };
      };

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

          # TODO: JetPack 5 uses TensorRT 8.5.2. Switch the x86_64-linux version to match.
          x86_64-linux-release = {
            version = "8.5.3";

            # Hashes are taken from:
            # https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/Packages
            debs = {
              variant = "cuda11.8";
              baseURL = "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64";
              hashes = {
                libnvinfer-bin = "096e10ed0f1c942fbb1738a204c39094df2ad0b09e30513272b469b51f35adf2";
                libnvinfer-dev = "10538b66701a3c376d1df0071b8e6ad65b3303d2391323c64aff952b450758c5";
                libnvinfer-plugin-dev = "d75f3d1ef74fb79f9fe66d0ddf955c1fdb26422af5eb1d96b9eb0dd51ba20f30";
                libnvinfer-plugin8 = "bed59dbeafa9beaac6f52b6ec757e2cde935b9c057fa9006a832516feea6d937";
                libnvinfer-samples = "d69dc07e980387fc66056fcaa8627405586539b77424c00d6dc3331ebb5d6257";
                libnvinfer8 = "6c9eee023d871613d6dcee07d671fb24a0e2a7e4d6b874fd3a27de0144158314";
                libnvonnxparsers-dev = "444407ebfd2c3f92b9ce5e463a10cdc5b7a06a13ba9ecb91befb501d7f70e78f";
                libnvonnxparsers8 = "11175938edd375dde52bca497916417070a642e95db3235ac7bbf646c2023213";
                libnvparsers-dev = "162d887444c90f054f1c4c391ed1a3b8f78258a612d00515b6c77a3a03a44fd2";
                libnvparsers8 = "2ecfd6ebfd5065e7871fca5ca9c1f50fb421003a56823a2f56107e104c5d2756";
              };
            };
          };
        in
        finalCudaPackages.debWrapBuildRedist {
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

      cuda_cccl = finalCudaPackages.debWrapBuildRedist {
        sourceName = "cuda-thrust";
        drv = prevCudaPackages.cuda_cccl;
      };

      # NOTE: CUDA 11.4 doesn't provide cuda-profiler-api for x86_64-linux, so we repackage the debian for it.
      cuda_profiler_api = finalCudaPackages.debWrapBuildRedist {
        drv = prevCudaPackages.cuda_profiler_api;
        # Need additional normalization because the CUDA version is different from the one used in the package set.
        extraDebNormalization = optionalString (system == "x86_64-linux") ''
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
  # The two exceptions to this are cuda_profiler_api and TensorRT, which we also provide, since we package it for both Jetson and x86_64-linux.
  if !hasAttr name prevCudaPackages || (canUseOurPackageVersion && (elem name [ "cuda_profiler_api" "tensorrt" ] || canUseOurPackagePlatform)) then
    value
  else
    getAttr name prevCudaPackages
  )
  newCudaPackages
