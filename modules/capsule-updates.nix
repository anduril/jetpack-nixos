{ config, lib, pkgs, utils, ... }:

let
  inherit (lib)
    mkIf
    mkOption
    mkRenamedOptionModule
    types
    ;

  cfg = config.hardware.nvidia-jetpack;

  canUpdateFirmware = cfg.firmware.autoUpdate && cfg.som != "generic" && cfg.flashScriptOverrides.targetBoard != null;

  updateFirmware = pkgs.writeShellApplication {
    name = "update-jetson-firmware";
    runtimeInputs = [ pkgs.coreutils config.systemd.package pkgs.nvidia-jetpack.otaUtils ];
    text = ''
      # If this script is not run on real hardware, don't attempt to perform an
      # update. This script could potentially run in a few places, for example
      # in <nixpkgs/nixos/lib/make-disk-image.nix>.
      if systemd-detect-virt --quiet; then
        echo "Skipping Jetson firmware update because we've detected we are in a virtualized environment."
        exit 0
      fi

      if [[ -v JETPACK_NIXOS_SKIP_CAPSULE_UPDATE ]]; then
        echo "Skipping Jetson firmware update because JETPACK_NIXOS_SKIP_CAPSULE_UPDATE is set"
        exit 0
      fi

      # Jetpack 5.0 didn't expose this DMI variable,
      if [[ ! -f /sys/devices/virtual/dmi/id/bios_version ]]; then
        echo "Unable to determine current Jetson firmware version."
        echo "You should reflash the firmware with the new version to ensure compatibility"
        exit 1
      fi

      if ! ota-check-firmware -b; then
        # Set efi vars here as well as in systemd service, in case we're
        # upgrading from an older nixos generation that doesn't have the
        # systemd service. Plus, this ota-setup-efivars will be from the
        # generation we're switching to, which can contain additional
        # fixes/improvements.
        ota-setup-efivars ${cfg.flashScriptOverrides.targetBoard}

        ota-apply-capsule-update ${pkgs.nvidia-jetpack.uefiCapsuleUpdate}
      else
        ota-abort-capsule-update
      fi
    '';
  };
in
{
  imports = [
    (mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "bootloader" "autoUpdate" ] [ "hardware" "nvidia-jetpack" "firmware" "autoUpdate" ])
  ];

  options = {
    hardware.nvidia-jetpack = {
      mountFirmwareEsp = mkOption {
        default = true;
        type = types.bool;
        description = "Whether to mount the ESP partition on eMMC under /opt/nvidia/esp on Xavier AGX platforms. Needed for capsule updates";
        internal = true;
      };

      firmware.autoUpdate = lib.mkEnableOption "automatic updates for Jetson firmware";
    };
  };

  config = mkIf cfg.enable {
    # Include the capsule-on-disk firmware update method with the bootloader
    # installation process so that firmware updates work with "nixos-rebuild boot".
    boot.loader = lib.mkIf canUpdateFirmware {
      systemd-boot.extraInstallCommands = lib.getExe updateFirmware;
      grub.extraInstallCommands = lib.getExe updateFirmware;
    };

    systemd.services.setup-jetson-efi-variables = lib.mkIf (cfg.flashScriptOverrides.targetBoard != null) {
      description = "Setup Jetson OTA UEFI variables";
      wantedBy = [ "multi-user.target" ];
      after = [ "opt-nvidia-esp.mount" ];
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = "${pkgs.nvidia-jetpack.otaUtils}/bin/ota-setup-efivars ${cfg.flashScriptOverrides.targetBoard}";
    };

    systemd.services.firmware-update = lib.mkIf canUpdateFirmware {
      wantedBy = [ "multi-user.target" ];
      after = [
        "${utils.escapeSystemdPath config.boot.loader.efi.efiSysMountPoint}.mount"
        "opt-nvidia-esp.mount"
      ];
      script =
        # NOTE: Our intention is to not apply any capsule update if the
        # user's intention is to "test" a new nixos config without having it
        # persist across reboots. "nixos-rebuild test" does not append a new
        # generation to /nix/var/nix/profiles for the system profile, so we
        # can compare that symlink to /run/current-system to see if our
        # current active config has been persisted as a generation. Note that
        # this check _may_ break down if not using nixos-rebuild and using
        # switch-to-configuration directly, however it is well-documented
        # that a user would need to self-manage their system profile's
        # generations if switching a system in that manner.
        lib.optionalString config.system.switch.enable ''
          if [[ -L /nix/var/nix/profiles/system ]]; then
            latest_generation=$(readlink -f /nix/var/nix/profiles/system)
            current_system=$(readlink -f /run/current-system)
            if [[ $latest_generation == /nix/store* ]] && [[ $latest_generation != "$current_system" ]]; then
              echo "Skipping capsule update, current active system not persisted to /nix/var/nix/profiles/system"
              exit 0
            fi
          fi
        '' + ''
          ${lib.getExe updateFirmware}
        '';
    };

    environment.systemPackages = lib.mkIf canUpdateFirmware [
      (pkgs.writeShellScriptBin "ota-apply-capsule-update-included" ''
        ${pkgs.nvidia-jetpack.otaUtils}/bin/ota-apply-capsule-update ${pkgs.nvidia-jetpack.uefiCapsuleUpdate}
      '')
    ];
  };
}
