{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkIf
    mkOption
    types;

  cfg = config.hardware.nvidia-jetpack;

  timeoutValue = cfg.firmware.uefi.bootMenuTimeout;

  efivarPath = "/sys/firmware/efi/efivars/Timeout-8be4df61-93ca-11d2-aa0d-00e098032b8c";

  # EFI variable format: 4-byte attributes (LE uint32) + 2-byte data (LE uint16)
  # Attributes: NV | BS | RT = 0x07
  setTimeoutScript = pkgs.writeShellScript "set-uefi-boot-timeout" ''
    set -euo pipefail

    timeout=${toString timeoutValue}
    efivar=${efivarPath}

    lo=$(( timeout & 0xFF ))
    hi=$(( (timeout >> 8) & 0xFF ))

    ${lib.getExe' pkgs.e2fsprogs "chattr"} -i "$efivar"

    printf '\x07\x00\x00\x00'"$(printf '\\x%02x\\x%02x' "$lo" "$hi")" > "$efivar"
  '';
in
{
  options.hardware.nvidia-jetpack.firmware.uefi.bootMenuTimeout = mkOption {
    type = types.ints.between 0 65535;
    default = 5;
    description = ''
      UEFI boot menu timeout in seconds. Controls how long the firmware
      waits for a keypress (ESC/F11/Enter) before auto-booting.

      Special values:
      - `0`: skip the timeout entirely and boot immediately.
      - `65535` (`0xFFFF`): wait indefinitely for user input.
        See `edk2/MdeModulePkg/Universal/BdsDxe/BdsEntry.c`
    '';
  };

  config = mkIf cfg.enable {
    systemd.services.set-uefi-boot-timeout = {
      description = "Set UEFI boot menu timeout EFI variable";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-efi-boot-generator.service" ];
      unitConfig.ConditionPathExists = efivarPath;
      unitConfig.ConditionPathIsMountPoint = "/sys/firmware/efi/efivars";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = setTimeoutScript;
      };
    };
  };
}
