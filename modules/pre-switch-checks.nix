{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.nvidia-jetpack;
in
{
  options.hardware.nvidia-jetpack.firmware.maxAllowedDowngrade = lib.mkOption {
    type = lib.types.enum [ "none" "patch" "minor" "major" ];
    default = "none";
    description = ''
      Maximum allowed L4T version downgrade level when switching NixOS generations.

      - `"none"`: No downgrades are allowed (default). This is the only supported setting.
      - `"patch"`: Patch version downgrades are allowed (e.g. 36.4.1 to 36.4.0),
        but minor and major downgrades are blocked.
      - `"minor"`: Minor and patch version downgrades are allowed (e.g. 36.4.0 to
        36.3.0), but major downgrades are blocked.
      - `"major"`: All downgrades are allowed, disables preSwitchCheck completely. 

      WARNING: Any setting other than `"none"` is untested. Downgrading the L4T
      version typically requires re-flashing the device firmware. Major version
      downgrades are almost guaranteed to not work or soft-brick the device.
    '';
  };

  # Prevent switching to a NixOS generation built for a lower L4T
  # version than the currently running firmware. Downgrading
  # requires re-flashing the device.
  config = lib.mkIf (cfg.enable && cfg.firmware.maxAllowedDowngrade != "major") {
    system.preSwitchChecks.jetpackDowngrade =
      # bash
      ''
        # shellcheck disable=SC2034
        incoming="''${1-}"
        action="''${2-}"
        if [ "$action" = "test" ]; then
          exit 0
        fi

        # Skip in chroot (e.g. nixos-install)
        if systemd-detect-virt --chroot 2>/dev/null; then
          exit 0
        fi

        if [ ! -f /sys/devices/virtual/dmi/id/bios_version ]; then
          echo "Warning: /sys/devices/virtual/dmi/id/bios_version not found, skipping Jetpack (L4T) downgrade check"
          exit 0
        fi

        # bios_version contains the L4T version, possibly with a unique hash suffix
        # Strip everything after major.minor.patch
        running_l4t="$(sed 's/^\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/' < /sys/devices/virtual/dmi/id/bios_version)"
        target_l4t="${pkgs.nvidia-jetpack.l4tMajorMinorPatchVersion}"
        max_downgrade="${cfg.firmware.maxAllowedDowngrade}"

        if [ "$max_downgrade" = "major" ]; then
          exit 0
        fi

        # Select which version components to compare based on maxAllowedDowngrade
        case "$max_downgrade" in
          minor)
            # Only block major version downgrades; minor+patch may decrease
            running_compare="''${running_l4t%%.*}"
            target_compare="''${target_l4t%%.*}"
            ;;
          patch)
            # Block major+minor downgrades; patch may decrease
            running_compare="''${running_l4t%.*}"
            target_compare="''${target_l4t%.*}"
            ;;
          *)
            # "none": block all downgrades
            running_compare="$running_l4t"
            target_compare="$target_l4t"
            ;;
        esac

        # If target is the lesser version after sorting, it's a downgrade
        oldest="$(printf '%s\n%s' "$target_compare" "$running_compare" | sort -V | head -n1)"
        if [ "$oldest" = "$target_compare" ] && [ "$target_compare" != "$running_compare" ]; then
          echo "Error: L4T version downgrade detected!"
          echo "Running L4T version: $running_l4t"
          echo "Target L4T version:  $target_l4t"
          echo "Downgrade protection level: $max_downgrade"
          echo "Downgrading the L4T version is not supported."
          echo "This requires re-flashing the device firmware."
          exit 1
        fi
      '';
  };
}
