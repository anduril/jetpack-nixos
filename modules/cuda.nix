{ config, lib, pkgs, options, ... }:

let
  inherit (lib)
    mkBefore
    mkOption
    mkIf
    types
    ;

  cfg = config.hardware.nvidia-jetpack;

  soc = import ../soc.nix { inherit lib; };

  thor2505 = (lib.hasPrefix "thor" cfg.som) && (lib.versionOlder lib.trivial.version "25.11");

  # Only `config` is used, so the overlay is not needed.
  nixpkgsArgs = import ../nixpkgs-args.nix { inherit lib; overlay = null; } {
    inherit (cfg) majorVersion;
    socType = soc.socTypeForSom cfg.som;
  };
  expectedCudaCapabilities = nixpkgsArgs.config.cudaCapabilities;
  readOnlyNixpkgs = !(options.nixpkgs ? localSystem);
  cudaSupport = pkgs.config.cudaSupport or false;
  cudaCapabilities = pkgs.config.cudaCapabilities or [ ];
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

          The resulting `pkgs` must have exactly this CUDA configuration, including when it is instantiated
          elsewhere and passed in (`nixpkgs.pkgs`, `readOnlyPkgs`): build it with jetpack-nixos's
          `lib.nixpkgsArgsFor`. When disabled, nothing is required of `pkgs`: it may have CUDA support
          from elsewhere, e.g. a package set shared with configurations that do use CUDA. Its packages are
          then the CUDA builds, so its derivations differ from those of the same configuration instantiating
          Nixpkgs itself without CUDA (as an installer with graphics disabled sharing its target's `pkgs` does).
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
      [
        {
          # Exact, not "at least": a package set built for more GPUs builds CUDA code differently, and one
          # built for fewer does not run here. This configuration only sets CUDA up itself when it
          # instantiates Nixpkgs; NixOS ignores `nixpkgs.config` when `nixpkgs.pkgs` is set.
          assertion = cfg.configureCuda -> (cudaSupport && cudaCapabilities == expectedCudaCapabilities);
          message = ''
            hardware.nvidia-jetpack.configureCuda is enabled, so `pkgs` must have `cudaSupport = true` and
            `cudaCapabilities = ${builtins.toJSON expectedCudaCapabilities}`, but it has `cudaSupport = ${lib.boolToString cudaSupport}` and
            `cudaCapabilities = ${builtins.toJSON cudaCapabilities}`. If `pkgs` is instantiated elsewhere
            (`nixpkgs.pkgs`), build it with jetpack-nixos's `lib.nixpkgsArgsFor`; otherwise check for modules
            overriding `nixpkgs.config.cudaCapabilities`.
          '';
        }
      ]
      ++ lib.optionals pkgs.config.cudaSupport [
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

    # Advertise support for CUDA. Not with `readOnlyPkgs`, where `pkgs` must
    # already have been built from `lib.nixpkgsArgsFor`.
    nixpkgs.config = mkIf (!readOnlyNixpkgs && cfg.configureCuda) (mkBefore (nixpkgsArgs.config // { cudaSupport = true; }));
  };
}
