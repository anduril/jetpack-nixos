#!/usr/bin/env bash
set -euo pipefail

source "@ota_helpers@"

targetBoard=$1

boardspec=$(tegra-boardspec)
compatspec=$(generate_compat_spec "$boardspec")

detect_can_write_runtime_uefi_vars "$boardspec"

if [[ ! -e /sys/firmware/efi/efivars/TegraPlatformSpec-781e084c-a330-417c-b678-38e696380cb9 ]]; then
  set_efi_var TegraPlatformSpec-781e084c-a330-417c-b678-38e696380cb9 "\x07\x00\x00\x00${boardspec}-${targetBoard}-"
fi

if [[ ! -e /sys/firmware/efi/efivars/TegraPlatformCompatSpec-781e084c-a330-417c-b678-38e696380cb9 ]]; then
    # TODO: We should also replace this value if ours is different
    set_efi_var TegraPlatformCompatSpec-781e084c-a330-417c-b678-38e696380cb9 "\x07\x00\x00\x00${compatspec}-${targetBoard}-"
fi
