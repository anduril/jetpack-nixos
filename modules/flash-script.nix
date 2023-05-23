{ config, pkgs, lib, ... }:

# Convenience package that allows you to set options for the flash script using the NixOS module system.
# You could do the overrides yourself if you'd prefer.
let
  inherit (lib)
    mkEnableOption
    mkOption
    types;

  cfg = config.hardware.nvidia-jetpack;
in
{
  imports = with lib; [
    (mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "bootloader" "autoUpdate" ] [ "hardware" "nvidia-jetpack" "firmware" "autoUpdate" ])
    (mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "bootloader" "logo" ] [ "hardware" "nvidia-jetpack" "firmware" "uefi" "logo" ])
    (mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "bootloader" "debugMode" ] [ "hardware" "nvidia-jetpack" "firmware" "uefi" "debugMode" ])
    (mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "bootloader" "errorLevelInfo" ] [ "hardware" "nvidia-jetpack" "firmware" "uefi" "errorLevelInfo" ])
    (mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "bootloader" "edk2NvidiaPatches" ] [ "hardware" "nvidia-jetpack" "firmware" "uefi" "edk2NvidiaPatches" ])
  ];

  options = {
    hardware.nvidia-jetpack = {
      firmware = {
        autoUpdate = lib.mkEnableOption "automatic updates for Jetson firmware";

        uefi = {
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
            default = cfg.firmware.uefi.debugMode;
          };

          edk2NvidiaPatches = mkOption {
            type = types.listOf types.path;
            default = [];
          };

          capsuleAuthentication = {
            enable = mkEnableOption "capsule update authentication";

            publicCertificateDerFile = mkOption {
              type = lib.types.path;
              description = lib.mdDoc ''
                The path to the public certificate (in DER format) that will be
                used for validating capsule updates. Capsule files must be signed
                with a private key in the same certificate chain. This file will
                be included in the EDK2 build.
              '';
            };

            trustedPublicCertPemFile = mkOption {
              type = lib.types.path;
              description = lib.mdDoc ''
                The path to the public certificate (in PEM format) that will be
                used when signing capsule payloads.
              '';
            };

            otherPublicCertPemFile = mkOption {
              type = lib.types.path;
              description = lib.mdDoc ''
                The path to another public certificate (in PEM format) that will
                be used when signing capsule payloads. This can be the same as
                `trustedPublicCertPem`, but it can also be an intermediate
                certificate further down in the chain of your PKI.
              '';
            };

            signerPrivateCertPemFile = mkOption {
              type = lib.types.path;
              description = lib.mdDoc ''
                The path to the private certificate (in PEM format) that will be
                used for signing capsule payloads.
              '';
            };

            requiredSystemFeatures = lib.mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = lib.mdDoc ''
                Additional `requiredSystemFeatures` to add to derivations which
                make use of capsule authentication private keys.
              '';
            };
          };
        };

        optee = {
          patches = mkOption {
            type = types.listOf types.path;
            default = [];
          };

          extraMakeFlags = mkOption {
            type = types.listOf types.str;
            default = [];
          };
        };

        eksFile = mkOption {
          type = types.nullOr types.path;
          default = null;
        };

        # See: https://docs.nvidia.com/jetson/archives/r35.3.1/DeveloperGuide/text/SD/Security/SecureBoot.html#prepare-an-sbk-key
        secureBoot = {
          pkcFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to Public Key Cryptography (PKC) .pem file used to validate authenticity and integrity of firmware partitions. Do not include this file in your /nix/store. Instead, use a sandbox exception to provide access to the key";
            example = "/run/keys/jetson/xavier_pkc.pem";
          };

          sbkFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to Secure Boot Key (SBK) file used to encrypt firmware partitions. Do not include this file in your /nix/store.  Instead, use a sandbox exception to provide access to the key";
            example = "/run/keys/jetson/xavier_skb.key";
          };

          requiredSystemFeatures = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Additional requiredSystemFeatures to add to derivations which make use of secure boot keys";
          };
        };

        # Firmware variants. For most normal usage, you shouldn't need to set this option
        variants = lib.mkOption {
          internal = true;
          type = types.listOf (types.submodule ({ config, name, ... }: {
            options = {
              boardid = lib.mkOption {
                type = types.str;
              };
              boardsku = lib.mkOption {
                type = types.str;
              };
              fab = lib.mkOption {
                type = types.str;
              };
              boardrev = lib.mkOption {
                type = types.str;
                default = "";
              };
              fuselevel = lib.mkOption {
                type = types.str; # TODO: Enum?
                default = "fuselevel_production";
              };
              chiprev = lib.mkOption {
                type = types.str;
                default = "";
              };
            };
          }));
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

        fuseArgs = mkOption {
          type = types.listOf types.str;
          description = "Arguments to apply to fusing script. DO NOT INCLUDE private files in fuseArgs (such as the odmfuse.xml file). Instead provide them at runtime on the command line";
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

    hardware.nvidia-jetpack.flashScriptOverrides.flashArgs = lib.mkAfter (
      lib.optional (cfg.firmware.secureBoot.pkcFile != null) "-u ${cfg.firmware.secureBoot.pkcFile}" ++
      lib.optional (cfg.firmware.secureBoot.sbkFile != null) "-v ${cfg.firmware.secureBoot.sbkFile}" ++
      [ cfg.flashScriptOverrides.configFileName "mmcblk0p1" ]
    );

    hardware.nvidia-jetpack.flashScriptOverrides.fuseArgs = lib.mkAfter [ cfg.flashScriptOverrides.configFileName ];

    hardware.nvidia-jetpack.firmware.uefi.edk2NvidiaPatches = [
      # Have UEFI use the device tree compiled into the firmware, instead of
      # using one from the kernel-dtb partition.
      # See: https://github.com/anduril/jetpack-nixos/pull/18
      ../edk2-uefi-dtb.patch
    ];

    # These are from l4t_generate_soc_bup.sh, plus some additional ones found in the wild.
    hardware.nvidia-jetpack.firmware.variants = lib.mkOptionDefault (rec {
      xavier-agx = [
        { boardid="2888"; boardsku="0001"; fab="400"; boardrev="D.0"; fuselevel="fuselevel_production"; chiprev="2"; }
        { boardid="2888"; boardsku="0001"; fab="400"; boardrev="E.0"; fuselevel="fuselevel_production"; chiprev="2"; } # 16GB
        { boardid="2888"; boardsku="0004"; fab="400"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; } # 32GB
        { boardid="2888"; boardsku="0005"; fab="402"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; } # 64GB
      ];
      xavier-nx = [ # Dev variant
        { boardid="3668"; boardsku="0000"; fab="100"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; }
        { boardid="3668"; boardsku="0000"; fab="301"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; }
      ];
      xavier-nx-emmc = [ # Prod variant
        { boardid="3668"; boardsku="0001"; fab="100"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; }
        { boardid="3668"; boardsku="0003"; fab="301"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; }
      ];

      orin-agx = [
        { boardid="3701"; boardsku="0000"; fab="300"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; }
        { boardid="3701"; boardsku="0004"; fab="300"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # 32GB
        { boardid="3701"; boardsku="0005"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # 64GB
      ];

      orin-nano = [
        { boardid = "3767"; boardsku = "0000"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # Orin NX 16GB
        { boardid = "3767"; boardsku = "0001"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # Orin NX 8GB
        { boardid = "3767"; boardsku = "0003"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # Orin Nano 8GB
        { boardid = "3767"; boardsku = "0005"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # Orin Nano devkit module
        { boardid = "3767"; boardsku = "0004"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # Orin Nano 4GB
      ];
      orin-nx = orin-nano;
    }.${cfg.som} or (throw "Unable to set default firmware variants since som is unset"));

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

    boot.loader.systemd-boot.extraInstallCommands = lib.mkIf (cfg.bootloader.autoUpdate && cfg.som != null && cfg.flashScriptOverrides.targetBoard != null) ''
      # Jetpack 5.0 didn't expose this DMI variable,
      if [[ ! -f /sys/devices/virtual/dmi/id/bios_version ]]; then
        echo "Unable to determine current Jetson firmware version."
        echo "You should reflash the firmware with the new version to ensure compatibility"
      else
        CUR_VER=$(cat /sys/devices/virtual/dmi/id/bios_version)
        NEW_VER=${pkgs.nvidia-jetpack.l4tVersion}

        if [[ "$CUR_VER" != "$NEW_VER" ]]; then
          echo "Current Jetson firmware version is: $CUR_VER"
          echo "New Jetson firmware version is: $NEW_VER"
          echo

          # Set efi vars here as well as in systemd service, in case we're
          # upgrading from an older nixos generation that doesn't have the
          # systemd service. Plus, this ota-setup-efivars will be from the
          # generation we're switching to, which can contain additional
          # fixes/improvements.
          ${pkgs.nvidia-jetpack.otaUtils}/bin/ota-setup-efivars ${cfg.flashScriptOverrides.targetBoard}

          ${pkgs.nvidia-jetpack.otaUtils}/bin/ota-apply-capsule-update ${config.system.build.jetsonDevicePkgs.uefiCapsuleUpdate}
        fi
      fi
    '';

    environment.systemPackages = lib.mkIf (cfg.bootloader.autoUpdate && cfg.som != null && cfg.flashScriptOverrides.targetBoard != null) [
      (pkgs.writeShellScriptBin "ota-apply-capsule-update-included" ''
        ${pkgs.nvidia-jetpack.otaUtils}/bin/ota-apply-capsule-update ${config.system.build.jetsonDevicePkgs.uefiCapsuleUpdate}
      '')
    ];
  };
}
