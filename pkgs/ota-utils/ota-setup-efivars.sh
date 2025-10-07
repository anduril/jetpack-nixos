#!/usr/bin/env bash
set -euo pipefail

source "@ota_helpers@"

targetBoard=$1

boardspec=$(tegra-boardspec)
compatspec=$(generate_compat_spec "$boardspec")

detect_can_write_runtime_uefi_vars "$boardspec"

# Cache BootChainFwStatus so we can report status to user in ota-check-firmware
# the cache is invalidated upon reboot: /var/run is a tmpfs
if [[ ! -f /var/run/tegra-bootchainfwstatus && -e /sys/firmware/efi/efivars/BootChainFwStatus-781e084c-a330-417c-b678-38e696380cb9 ]]; then
  get_efi_int BootChainFwStatus-781e084c-a330-417c-b678-38e696380cb9 >/var/run/tegra-bootchainfwstatus
fi

# We have to remove the BootChainFwStatus so we can apply future capsule updates
if [[ -f /sys/firmware/efi/efivars/BootChainFwStatus-781e084c-a330-417c-b678-38e696380cb9 ]]; then
  echo "Detected capsule update failure."
  rm_efi_var BootChainFwStatus-781e084c-a330-417c-b678-38e696380cb9
fi

boardspec="${boardspec}-${targetBoard}-"
compatspec="${compatspec}-${targetBoard}-"

# TegraPlatformSpec is LOCK_ON_CREATE
if [[ ! -e /sys/firmware/efi/efivars/TegraPlatformSpec-781e084c-a330-417c-b678-38e696380cb9 ]]; then
  set_efi_var TegraPlatformSpec-781e084c-a330-417c-b678-38e696380cb9 "\x07\x00\x00\x00${boardspec}"
fi

# TegraPlatformCompatSpec is LOCK_NONE, we can change it. Only change it if it's not expected value
if [[ "$(get_efi_str TegraPlatformCompatSpec-781e084c-a330-417c-b678-38e696380cb9)" != "${compatspec}" ]]; then
  set_efi_var TegraPlatformCompatSpec-781e084c-a330-417c-b678-38e696380cb9 "\x07\x00\x00\x00${compatspec}"
fi
