# Internal hook, used by cudatoolkit and cuda redist packages
# to accommodate automatic CUDAToolkit_ROOT construction
{ config
, cudaConfig
, lib
, makeSetupHook
}:
let
  inherit (cudaConfig) hostRedistSystem;
  inherit (lib.attrsets) attrValues;
  inherit (lib.lists) any optionals;
  inherit (lib.trivial) id;

  isBadPlatform = any id (attrValues finalAttrs.passthru.badPlatformsConditions);

  finalAttrs = {
    name = "mark-for-cudatoolkit-root-hook";
    passthru.badPlatformsConditions = {
      "Platform is not supported" = hostRedistSystem == "unsupported";
    };
    meta = {
      description = "Setup hook which marks CUDA packages for inclusion in CUDA environment variables";
      broken = lib.warnIfNot config.cudaSupport "CUDA support is disabled and you are building a CUDA package (${finalAttrs.name}); expect breakage!" false;
      platforms = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      badPlatforms = optionals isBadPlatform finalAttrs.meta.platforms;
    };
  };
in
makeSetupHook finalAttrs ./mark-for-cudatoolkit-root-hook.sh
