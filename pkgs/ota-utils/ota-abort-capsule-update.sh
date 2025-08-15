#!/usr/bin/env bash
set -euo pipefail

source "@ota_helpers@"

boardspec=$(tegra-boardspec)
detect_can_write_runtime_uefi_vars "$boardspec"

# Check for @efiSysMountPoint@ (defaults to /boot) being an ESP. On Xavier AGX,
# even though the efi vars need to be written to an ESP on the emmc, capsule
# updates can still be written to an ESP partition at @efiSysMountPoint@ on
# other devices (e.g. nvme)
if ! mountpoint -q @efiSysMountPoint@; then
  echo "@efiSysMountPoint@ is not mounted"
  exit 1
fi

set_efi_var OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c "\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"

rm -f @efiSysMountPoint@/EFI/UpdateCapsule/TEGRA_BL.Cap
