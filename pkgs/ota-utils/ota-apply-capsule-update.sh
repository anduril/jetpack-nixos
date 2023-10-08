#!/usr/bin/env bash
set -euo pipefail

source "@ota_helpers@"

capsuleFile=$1

boardspec=$(tegra-boardspec)
detect_can_write_runtime_uefi_vars "$boardspec"

# Check for /boot being an ESP. On Xavier AGX, even though the efi vars need to
# be written to an ESP on the emmc, capsule updates can still be written to an
# ESP partition at /boot on other devices (e.g. nvme)
if ! mountpoint -q /boot; then
    echo "/boot is not mounted"
    exit 1
fi

mkdir -p /boot/EFI/UpdateCapsule
cp "$capsuleFile" /boot/EFI/UpdateCapsule/TEGRA_BL.Cap
sync /boot/EFI/UpdateCapsule/TEGRA_BL.Cap

set_efi_var OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c "\x07\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00"

echo "New Jetson firmware will be applied during the next reboot."
echo "The next reboot may take an extra 5 minutes or so."
echo "Do not disconnect power during the reboot, or the firmware upgrade will not be applied"
