#
# This file contains modified helper functions from meta-tegra recipes-bsp/tegra-binaries/tegra-helper-scripts/initrd-flash.sh
# Copyright (c) 2023 The OE4Tegra Project
# Licensed under MIT.

set -euo pipefail

source @ota_helpers_func@

signed_images=$1

matching_boardspec=

find_matching_spec() {
    local boardspec=$(tegra-boardspec)

    # Generate the "compat" boardspec for this one to match against
    boardspec=$(generate_compat_spec "$boardspec")

    local my_boardid=$(echo "$boardspec" | cut -d- -f1)
    local my_fab=$(echo "$boardspec" | cut -d- -f2)
    local my_boardsku=$(echo "$boardspec" | cut -d- -f3)
    local my_boardrev=$(echo "$boardspec" | cut -d- -f4)
    local my_fuselevel=$(echo "$boardspec" | cut -d- -f5)
    local my_chiprev=$(echo "$boardspec" | cut -d- -f6)

    for dirpath in "$signed_images"/*; do
        curspec=$(basename "$dirpath")
        cur_boardid=$(echo "$curspec" | cut -d- -f1)
        cur_fab=$(echo "$curspec" | cut -d- -f2)
        cur_boardsku=$(echo "$curspec" | cut -d- -f3)
        cur_boardrev=$(echo "$curspec" | cut -d- -f4)
        cur_fuselevel=$(echo "$curspec" | cut -d- -f5)
        cur_chiprev=$(echo "$curspec" | cut -d- -f6)

        if [[ "$my_boardid" != "" ]]   && [[ "$cur_boardid" != "" ]]   && [[ "$cur_boardid" != "$my_boardid" ]]; then continue; fi
        if [[ "$my_fab" != "" ]]       && [[ "$cur_fab" != "" ]]       && [[ "$cur_fab" != "$my_fab" ]]; then continue; fi
        if [[ "$my_boardsku" != "" ]]  && [[ "$cur_boardsku" != "" ]]  && [[ "$cur_boardsku" != "$my_boardsku" ]]; then continue; fi
        if [[ "$my_boardrev" != "" ]]  && [[ "$cur_boardrev" != "" ]]  && [[ "$cur_boardrev" != "$my_boardrev" ]]; then continue; fi
        if [[ "$my_fuselevel" != "" ]] && [[ "$cur_fuselevel" != "" ]] && [[ "$cur_fuselevel" != "$my_fuselevel" ]]; then continue; fi
        if [[ "$my_chiprev" != "" ]]   && [[ "$cur_chiprev" != "" ]]   && [[ "$cur_chiprev" != "$my_chiprev" ]]; then continue; fi

        matching_boardspec=$curspec
        break
    done

    if [[ -z "$matching_boardspec" ]]; then
        echo "Could not find a matching boardspec in signed firmware directory for: $boardspec"
        echo "Are you sure you created the right signed firmware for this type of device?"
        exit 1
    fi
}

program_spi_partition() {
    local partname="$1"
    local part_offset="$2"
    local part_size="$3"
    local part_file="$4"
    local file_size=0

    if [[ -n "$part_file" ]]; then
        file_size=$(stat -c "%s" "$part_file")
        if [[ -z "$file_size" ]]; then
            echo "ERR: could not retrieve file size of $part_file" >&2
            return 1
        fi
    fi
    if [[ "$file_size" != 0 ]]; then
        echo "Writing $part_file (size=$file_size) to $partname (offset=$part_offset)"
        if ! mtd_debug write /dev/mtd0 "$part_offset" "$file_size" "$part_file"; then
            return 1
        fi
    fi
    # Multiple copies of the BCT get installed at erase-block boundaries
    # within the defined BCT partition
    if [ "$partname" = "BCT" ]; then
        local slotsize
        slotsize=$(cat /sys/class/mtd/mtd0/erasesize)
        if [ -z "$slotsize" ]; then
            return 1
        fi
        local rounded_slot_size=$(( ((slotsize + 511) / 512) * 512 ))
        local curr_offset=$(( part_offset + rounded_slot_size ))
        local copycount=$(( part_size / rounded_slot_size ))
        local i=1
        while [[ $i -lt $copycount ]]; do
            echo "Writing $part_file to BCT+$i (offset=$curr_offset)"
            if ! mtd_debug write /dev/mtd0 "$curr_offset" "$file_size" "$part_file"; then
                return 1
            fi
            i=$((i + 1))
            curr_offset=$((curr_offset + rounded_slot_size))
        done
    fi
    return 0
}

program_mmcboot_partition() {
    local partname="$1"
    local part_offset="$2"
    local part_size="$3"
    local part_file="$4"
    local file_size=0
    local bootpart="/dev/mmcblk0boot0"

    if [[ -z "$BOOTPART_SIZE" ]]; then
        echo "ERR: boot partition size not set" >&2
        return 1
    fi
    if [[ "$part_offset" -ge "$BOOTPART_SIZE" ]]; then
        part_offset=$((part_offset - BOOTPART_SIZE))
        bootpart="/dev/mmcblk0boot1"
    fi
    if [[ -n "$part_file" ]]; then
        file_size=$(stat -c "%s" "$part_file")
        if [ -z "$file_size" ]; then
            echo "ERR: could not retrieve file size of $part_file" >&2
            return 1
        fi
    fi
    if [[ "$file_size" -ne 0 ]]; then
        echo "Writing $part_file (size=$file_size) to $partname on $bootpart (offset=$part_offset)"
        if ! dd if="$part_file" of="$bootpart" bs=4096 seek="$part_offset" oflag=seek_bytes > /dev/null; then
            return 1
        fi
        # Multiple copies of the BCT get installed at 16KiB boundaries
        # within the defined BCT partition
        if [[ "$partname" = "BCT" ]]; then
            local slotsize=16384
            local curr_offset=$((part_offset + slotsize))
            local copycount=$((part_size / slotsize))
            local i=1
            while [[ $i -lt $copycount ]]; do
                echo "Writing $part_file (size=$file_size) to BCT+$i (offset=$curr_offset)"
                if ! dd if="$part_file" of="$bootpart" bs=4096 seek="$curr_offset" oflag=seek_bytes > /dev/null; then
                    return 1
                fi
                i=$((i + 1))
                curr_offset=$((curr_offset + slotsize))
            done
        fi
    fi
    return 0
}

erase_bootdev() {
    BOOTDEV_TYPE=

    # Detect type to erase
    while IFS=", " read -r partnumber partloc start_location partsize partfile partattrs partsha; do
        devnum=$(echo "$partloc" | cut -d':' -f 1)
        instnum=$(echo "$partloc" | cut -d':' -f 2)
        partname=$(echo "$partloc" | cut -d':' -f 3)
        # SPI is 3:0
        # eMMC boot blocks (boot0/boot1) are 0:3
        if [[ "$devnum" -eq 3 && "$instnum" -eq 0 ]]; then
            BOOTDEV_TYPE=spi
        elif [[ "$devnum" -eq 0 && "$instnum" -eq 3 ]]; then
            BOOTDEV_TYPE=mmcboot
        fi
    done < flash.idx

    if [ "$BOOTDEV_TYPE" = "mmcboot" ]; then
        if [[ ! -b /dev/mmcblk0boot0 ]] || [[ ! -b /dev/mmcblk0boot1 ]]; then
            echo "ERR: eMMC boot device, but mmcblk0bootX devices do not exist" >&2
            return 1
        fi
        BOOTPART_SIZE=$(( $(cat /sys/block/mmcblk0boot0/size) * 512))
        echo "0" > /sys/block/mmcblk0boot0/force_ro
        echo "0" > /sys/block/mmcblk0boot1/force_ro
        echo "Erasing /dev/mmcblk0boot0"
        blkdiscard -f /dev/mmcblk0boot0
        echo "Erasing /dev/mmcblk0boot1"
        blkdiscard -f /dev/mmcblk0boot1
    elif [ "$BOOTDEV_TYPE" = "spi" ]; then
        if [ ! -e /dev/mtd0 ]; then
            echo "ERR: SPI boot device, but mtd0 device does not exist" >&2
            return 1
        fi
        echo "Erasing /dev/mtd0"
        flash_erase /dev/mtd0 0 0
    else
        echo "ERR: unknown boot device type: $BOOTDEV_TYPE" >&2
        return 1
    fi
}

write_partitions() {
    # shellcheck disable=SC2034
    while IFS=", " read -r partnumber partloc start_location partsize partfile partattrs partsha; do
        # Need to trim off leading blanks
        devnum=$(echo "$partloc" | cut -d':' -f 1)
        instnum=$(echo "$partloc" | cut -d':' -f 2)
        partname=$(echo "$partloc" | cut -d':' -f 3)
        # SPI is 3:0
        # eMMC boot blocks (boot0/boot1) are 0:3
        # eMMC user is 1:3
        # SDCard on SoM is 6:0 (Like on Xavier NX dev module)
        # NVMe (any external device) is 9:0
        if [[ "$devnum" -eq 3 && "$instnum" -eq 0 ]]; then
            if [[ "$partfile" != "" ]]; then
                program_spi_partition "$partname" "$start_location" "$partsize" "$partfile"
            fi
        elif [[ "$devnum" -eq 0 && "$instnum" -eq 3 ]]; then
            if [[ "$partfile" != "" ]]; then
                program_mmcboot_partition "$partname" "$start_location" "$partsize" "$partfile"
            fi
        elif [[ "$devnum" -eq 1 && "$instnum" -eq 3 ]] || [[ "$devnum" -eq 6 && "$instnum" -eq 0 ]]; then
            if [[ "$partfile" != "" ]]; then
            echo "Writing $partfile (size=$partsize) to $partname on /dev/mmcblk0 (offset=$start_location)"
            file_size=$(stat -c "%s" "$partfile")
            if ! dd if="$partfile" of="/dev/mmcblk0" bs=4096 seek="$start_location" oflag=seek_bytes > /dev/null; then
                return 1
            fi
        fi
    fi
    done < flash.idx
}

find_matching_spec

# Enter directory containing firmware
cd "$signed_images"/"$matching_boardspec"

erase_bootdev
write_partitions

echo Finished flashing device
