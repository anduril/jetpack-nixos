#!/usr/bin/env bash

FW_VER=$(cat /sys/devices/virtual/dmi/id/bios_version)
SW_VER=@l4tVersion@

echo "Current firmware version is: ${FW_VER}"
echo "Current software version is: ${SW_VER}"

if [[ "$FW_VER" != "$SW_VER" ]]; then
    exit 1
fi
