{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkBefore
    mkOption
    mkIf
    types
    ;

  cfg = config.hardware.nvidia-jetpack;

  thor2505 = (lib.hasPrefix "thor" cfg.som) && (lib.versionOlder lib.trivial.version "25.11");
in
{
  options = {
    hardware.nvidia-jetpack = {
      configureCuda = mkOption {
        default = config.hardware.graphics.enable;
        defaultText = "config.hardware.graphics.enable";
        type = types.bool;
        description = ''
          Configures the instance of Nixpkgs used for the system closure for Jetson devices.

          When enabled, Nixpkgs is instantiated with `config.cudaSupport` set to `true`, so all packages
          are built with CUDA support enabled. Additionally, `config.cudaCapabilities` is set based on the
          value of `hardware.nvidia-jetpack.som`, producing binaries targeting the specific Jetson SOM.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    # If NixOS has been configured with CUDA support, add additional assertions to make sure CUDA packages
    # being built have a chance of working.
    assertions =
      let
        inherit (pkgs.cudaPackages) cudaMajorMinorVersion cudaAtLeast cudaOlder;
      in
      lib.optionals pkgs.config.cudaSupport [
        {
          assertion = !cudaOlder "11.4";
          message = "JetPack NixOS does not support CUDA 11.3 or earlier: `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
        }
        {
          assertion = cfg.majorVersion == "5" -> (cudaAtLeast "11.4" && cudaOlder "12.3");
          message = "JetPack NixOS 5 supports CUDA 11.4 (natively) - 12.2 (with `cuda_compat`): `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
        }
        {
          assertion = cfg.majorVersion == "6" -> (cudaAtLeast "12.4" && cudaOlder "13.0");
          message = "JetPack NixOS 6 supports CUDA 12.4 (natively) - 12.9 (with `cuda_compat`): `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
        }
        {
          assertion = cfg.majorVersion == "7" -> cudaAtLeast "13.0";
          message = "JetPack NixOS 7 supports CUDA 13.0 (natively): `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
        }
        {
          assertion = !(thor2505 && (config.hardware.nvidia-jetpack.configureCuda || pkgs.config.cudaSupport));
          message = "CUDA 13 support is not available in NixOS 25.05. Please disable CUDA.";
        }
      ];

    hardware.nvidia-jetpack.configureCuda = lib.mkIf thor2505 (lib.mkForce false);

    # Advertise support for CUDA.
    nixpkgs.config = mkIf cfg.configureCuda (mkBefore {
      cudaSupport = true;
      cudaCapabilities =
        let
          isGeneric = cfg.som == "generic";
          isXavier = lib.hasPrefix "xavier-" cfg.som;
          isOrin = lib.hasPrefix "orin-" cfg.som;
          isThor = lib.hasPrefix "thor-" cfg.som;
        in
        lib.optionals (isXavier || isGeneric) [ "7.2" ] ++
        lib.optionals (isOrin || isGeneric) [ "8.7" ] ++
        lib.optionals isThor [ "11.0" ];
    });
  };
}
