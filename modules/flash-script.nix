{ config, pkgs, lib, ... }:

# Convenience package that allows you to set options for the flash script using the NixOS module system.
# You could do the overrides yourself if you'd prefer.
let
  inherit (lib)
    mkDefault
    mkIf
    mkOption
    types;

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
          type = types.nullOr types.str;
          default = null;
          description = "Target board to use when flashing (should match .conf in BSP package)";
        };

        configFileName = mkOption {
          type = types.str;
          default = cfg.flashScriptOverrides.targetBoard;
          description = "Name of configuration file to use when flashing (excluding .conf suffix).  Defaults to targetBoard";
        };

        flashArgs = mkOption {
          type = types.listOf types.str;
          description = "Arguments to apply to flashing script";
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

      devicePkgs = mkOption {
        type = types.attrsOf types.anything;
        readOnly = true;
        internal = true;
        description = "Flashing packages associated with this NixOS configuration";
      };
    };
  };

  config = let
    devicePkgs = pkgs.nvidia-jetpack.devicePkgsFromNixosConfig config;
  in {
    hardware.nvidia-jetpack.flashScript = devicePkgs.flashScript; # Left for backwards-compatibility
    hardware.nvidia-jetpack.devicePkgs = devicePkgs; # Left for backwards-compatibility
    system.build.jetsonDevicePkgs = devicePkgs;

    hardware.nvidia-jetpack.flashScriptOverrides.flashArgs = lib.mkAfter [ cfg.flashScriptOverrides.configFileName "mmcblk0p1" ];

    hardware.nvidia-jetpack.bootloader.edk2NvidiaPatches = [
      # Have UEFI use the device tree compiled into the firmware, instead of
      # using one from the kernel-dtb partition.
      # See: https://github.com/anduril/jetpack-nixos/pull/18
      ../edk2-uefi-dtb.patch
    ];

    systemd.services = lib.mkIf (cfg.flashScriptOverrides.targetBoard != null) {
      setup-jetson-efi-variables = {
        enable = true;
        description = "Setup Jetson OTA UEFI variables";
        wantedBy = [ "multi-user.target" ];
        after = [ "opt-nvidia-esp.mount" ];
        serviceConfig.Type = "oneshot";
        serviceConfig.ExecStart = "${pkgs.nvidia-jetpack.otaUtils}/bin/ota-setup-efivars ${cfg.flashScriptOverrides.targetBoard}";
      };
    };
  };
}
