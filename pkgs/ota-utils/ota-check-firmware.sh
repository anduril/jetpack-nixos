#!/usr/bin/env bash

CURRENT_FW_VER=$(cat /sys/devices/virtual/dmi/id/bios_version || echo Unknown)
EXPECTED_FW_VER=$(cat /etc/jetson_expected_bios_version || echo Unknown)

echo "Current firmware version is: ${CURRENT_FW_VER}"
echo "Expected firmware version is: ${EXPECTED_FW_VER}"

if [[ "$CURRENT_FW_VER" != "$EXPECTED_FW_VER" ]]; then
    exit 1
fi
