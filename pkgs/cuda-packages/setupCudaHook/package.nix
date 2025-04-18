# Currently propagated by cuda_nvcc or cudatoolkit, rather than used directly
{ backendStdenv
, config
, cudaConfig
, lib
, makeSetupHook
}:
let
  inherit (backendStdenv) cc hostPlatform;
  inherit (cudaConfig) hostRedistSystem;
  inherit (lib.attrsets) attrValues;
  inherit (lib.lists) any optionals;
  inherit (lib.trivial) id;

  isBadPlatform = any id (attrValues finalAttrs.passthru.badPlatformsConditions);

  finalAttrs = {
    name = "setup-cuda-hook";

    # TODO(@connorbaker): The setup hook tells CMake not to link paths which include a GCC-specific compiler
    # path from nvccStdenv's host compiler. Generalize this to Clang as well!
    substitutions = {
      # Required in addition to ccRoot as otherwise bin/gcc is looked up
      # when building CMakeCUDACompilerId.cu
      ccFullPath = "${cc}/bin/${cc.targetPrefix}c++";
      ccVersion = cc.version;
      unwrappedCCRoot = cc.cc.outPath;
      unwrappedCCLibRoot = cc.cc.lib.outPath;
      hostPlatformConfig = hostPlatform.config;
      setupCudaHook = placeholder "out";
    };

    passthru.badPlatformsConditions = {
      "Platform is not supported" = hostRedistSystem == "unsupported";
    };

    meta = {
      description = "Setup hook for CUDA packages";
      broken = lib.warnIfNot config.cudaSupport "CUDA support is disabled and you are building a CUDA package (${finalAttrs.name}); expect breakage!" false;
      platforms = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      badPlatforms = optionals isBadPlatform finalAttrs.meta.platforms;
    };
  };
in
makeSetupHook finalAttrs ./setup-cuda-hook.sh
