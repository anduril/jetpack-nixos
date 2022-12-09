{ config, pkgs, lib, ... }:

# Convenience package that allows you to set options for the flash script using the NixOS module system.
# You could do the overrides yourself if you'd prefer.
let
  inherit (lib)
    mkDefault
    mkIf
    mkOption
    types;

  # Ugly reimport of nixpkgs. This is probably not the right way to do this.
  pkgsx86 = import pkgs.path { system = "x86_64-linux"; };

  cfg = config.hardware.nvidia-jetpack;
in
{
  options = {
    hardware.nvidia-jetpack = {
      bootloader = {
        logo = mkOption {
          type = types.nullOr types.path;
          # This NixOS default logo is made available under a CC-BY license. See the repo for details.
          default = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/e7d4050f2bb39a8c73a31a89e3d55f55536541c3/logo/nixos.svg";
            sha256 = "sha256-E+qpO9SSN44xG5qMEZxBAvO/COPygmn8r50HhgCRDSw=";
          };
          description = "Optional path to a boot logo that will be converted and cropped into the format required";
        };

        debugMode = mkOption {
          type = types.bool;
          default = false;
        };

        errorLevelInfo = mkOption {
          type = types.bool;
          default = cfg.bootloader.debugMode;
        };

        edk2NvidiaPatches = mkOption {
          type = types.listOf types.path;
          default = [];
        };
      };

      flashScriptOverrides = {
        targetBoard = mkOption {
          type = types.str;
          description = "Target board to use when flashing (should match .conf in BSP package)";
        };

        flashArgs = mkOption {
          type = types.str;
          description = "Arguments to apply to flashing script";
          default = "${cfg.flashScriptOverrides.targetBoard} mmcblk0p1";
        };

        partitionTemplate = mkOption {
          type = types.path;
          description = ".xml file describing partition template to use when flashing";
        };

        postPatch = mkOption {
          type = types.lines;
          default = "";
          description = "Additional commands to run when building flash-tools";
        };
      };

      flashScript = mkOption {
        type = types.package;
        readOnly = true;
        internal = true;
        description = "Script to flash the xavier device";
      };
    };
  };

  config = {
    # Totally ugly reimport of nixpkgs so we can get a native x86 version. This
    # is probably not the right way to do it, since overlays wouldn't get
    # applied in the new import of nixpkgs.
    hardware.nvidia-jetpack.flashScript = ((import pkgs.path { system = "x86_64-linux"; }).callPackage ./default.nix {}).flashScriptFromNixos config;
  };
}
