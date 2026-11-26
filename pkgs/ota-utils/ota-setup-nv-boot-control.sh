#!/usr/bin/env bash
set -euo pipefail

# Write the /etc/nv_boot_control.conf that NVIDIA's nvbootctrl reads. On stock
# L4T, flash.sh writes it into the rootfs. Here it is generated at boot from
# the module EEPROM, and /etc/nv_boot_control.conf links to it.
# See also: meta-tegra recipes-bsp/tools/setup-nv-boot-control and
# recipes-bsp/tegra-binaries/tegra-nv-boot-control-config

source "@ota_helpers@"

show_help() {
  echo "Usage: $0 [-c CHIP_ID] [-b OTA_BOOT_DEVICE] [-g OTA_GPT_DEVICE] TARGET_BOARD BOOTDEV"
  echo
  echo "Write /run/nv_boot_control.conf for nvbootctrl"
}

chipId=
otaBootDevice=
otaGptDevice=

while getopts ":hc:b:g:" opt; do
  case $opt in
  h)
    show_help
    exit 0
    ;;
  c)
    chipId=$OPTARG
    ;;
  b)
    otaBootDevice=$OPTARG
    ;;
  g)
    otaGptDevice=$OPTARG
    ;;
  *)
    show_help >&2
    exit 2
    ;;
  esac
done
shift $((OPTIND - 1))

if [[ $# -ne 2 ]]; then
  show_help >&2
  exit 2
fi

targetBoard=$1
bootDev=$2
conf=/run/nv_boot_control.conf

boardspec=$(tegra-boardspec)

{
  # As in meta-tegra's setup-nv-boot-control.sh.in
  echo "TNSPEC ${boardspec}-${targetBoard}-${bootDev}"
  if compatspec=$(generate_compat_spec "$boardspec"); then
    echo "COMPATIBLE_SPEC ${compatspec}-${targetBoard}-"
  fi

  # The disk that holds the root filesystem, if it is on one
  rootdev=$(findmnt -n -o SOURCE --nofsroot --target /)
  if [[ -b "$rootdev" ]]; then
    while read -r name type; do
      if [[ "$type" == "disk" ]]; then
        echo "TEGRA_BOOT_STORAGE ${name}"
        break
      fi
    done < <(lsblk -nrs -o NAME,TYPE "$rootdev")
  fi

  if [[ -n "$chipId" ]]; then
    echo "TEGRA_CHIPID ${chipId}"
  fi
  if [[ -n "$otaBootDevice" ]]; then
    echo "TEGRA_OTA_BOOT_DEVICE ${otaBootDevice}"
  fi
  if [[ -n "$otaGptDevice" ]]; then
    echo "TEGRA_OTA_GPT_DEVICE ${otaGptDevice}"
  fi
} >"${conf}.tmp"

chmod 0644 "${conf}.tmp"
mv -f "${conf}.tmp" "$conf"
