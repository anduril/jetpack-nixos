# shellcheck shell=bash
# Host side of board detection over RCM. Needs generate_compat_spec
# (pkgs/ota-utils/ota_helpers.sh).

# rcm_read_board <rcmDetect> <chip id> <work dir> [usb instance]: boots the mb2
# applet from rcmDetect and reads EEPROM and chip info into <work dir>/{uid.log,
# cvm.bin, chipinfo.bin}, then puts the device back into recovery, as NVIDIA's
# read_eeprom.func and read_ramcode.func do, but in one session.
rcm_read_board() {
  local chip=$2 work=$3 rc=0 inst
  inst=$(rcm_usb_instance "$chip" "${4-}") || return 1
  cp -r "$1/rcmdump_blob/." "$work"
  chmod -R u+w "$work"
  (
    cd "$work" || exit 1
    rcm_with_instance "$inst" <rcmdumpcmd.txt | "$BASH" >uid.log 2>&1 || {
      cat uid.log >&2
      echo "Error: the device is in recovery mode but didn't answer over USB. Reconnect the cable, put it back into recovery mode and retry." >&2
      exit 1
    }
    cat uid.log >&2
    ./tegrarcm_v2 --instance "$inst" --chip "$chip" 0 --oem platformdetails eeprom cvm cvm.bin >&2 &&
      ./tegrarcm_v2 --instance "$inst" --chip "$chip" 0 --oem platformdetails chip chipinfo.bin >&2 || {
      echo "Error: reading the board's EEPROM or chip info over USB failed; the device may have reset or been disconnected. Put it back into recovery mode and retry." >&2
      rc=1
    }
    ./tegrarcm_v2 --instance "$inst" --chip "$chip" 0 --reboot recovery >&2
    sleep 1
    exit $rc
  )
}

# rcm_usb_instance <chip id> [usb instance]: prints the USB instance
# (<busnum>-<devpath>, as flash.sh --usb-instance and tegrarcm_v2 --instance
# take it) of the device in recovery mode, the given one or else the only one.
# Such a device shows up as 0955:xx<chip> (nvautoflash.sh: 7023, 7223-7623 on
# T234; 7026, 7226, 7326 on T264), and this user must be able to open its
# /dev/bus/usb node. Fails with what to do otherwise. RCM_USB_DEVICES and
# RCM_USB_NODES override the sysfs and /dev/bus/usb directories (tests).
rcm_usb_instance() {
  local id=${1#0x} want=${2-} d vendor product inst node other=
  local -a found=()
  for d in "${RCM_USB_DEVICES:-/sys/bus/usb/devices}"/*/; do
    vendor=$(cat "$d/idVendor" 2>/dev/null) || continue
    [[ $vendor == 0955 ]] || continue
    product=$(cat "$d/idProduct" 2>/dev/null) || continue
    if [[ $product == ??"$id" ]]; then
      inst=$(cat "$d/busnum")-$(cat "$d/devpath")
      [[ -z $want || $want == "$inst" ]] || continue
      node=${RCM_USB_NODES:-/dev/bus/usb}/$(printf %03d/%03d "$(cat "$d/busnum")" "$(cat "$d/devnum")")
      if ! [[ -r $node && -w $node ]]; then
        echo "Error: the device in recovery mode (USB 0955:$product, instance $inst) is at $node, which this user can't open. Run as root, or add a udev rule giving your user access to 0955:$product, then retry." >&2
        return 1
      fi
      found+=("$inst")
    else
      other+=" 0955:$product"
    fi
  done
  if [[ ${#found[@]} -eq 1 ]]; then
    echo "${found[0]}"
    return 0
  elif [[ ${#found[@]} -gt 1 ]]; then
    echo "Error: several devices in recovery mode (USB instances: ${found[*]}). Pick one with --usb-instance <instance>." >&2
  elif [[ -n $want ]]; then
    echo "Error: no device in recovery mode at USB instance $want." >&2
  elif [[ -n $other ]]; then
    echo "Error: an NVIDIA device is connected (USB${other}) but not in recovery mode. Put it into recovery mode (hold the recovery button while powering on or resetting it) and retry." >&2
  else
    echo "Error: no NVIDIA device in recovery mode on USB. Connect the host to the device's flashing USB port, put the device into recovery mode (hold the recovery button while powering on or resetting it) and retry." >&2
  fi
  return 1
}

# rcm_with_instance <usb instance>: copies a tegrarcm_v2 command file from stdin
# with --instance added to each tegrarcm_v2 call, as tegraflash and
# l4t_initrd_flash_internal.sh add it.
rcm_with_instance() {
  sed "s|tegrarcm_v2 |tegrarcm_v2 --instance $1 |"
}

# chkbdinfo pads its output with a space; flash.sh's `eval` drops it.
_rcm_bd() {
  local v
  v=$("$1" "$2" "$3") || {
    echo "chkbdinfo $2 $3: $v" >&2
    return 1
  }
  read -r v <<<"$v"
  echo "$v"
}

# rcm_select_variant <variants> <chkbdinfo> <uid.log> <cvm.bin> <chipinfo.bin>
# prints the key of the firmware.variants entry for the dumped board. The
# board spec is read as flash.sh does (get_fuse_level, get_board_version,
# get_chip_info_details); the entry is the one flash-from-device would pick
# (generate_compat_spec, then the first <variants> line whose key matches
# field by field, an empty field matching anything). A chip SKU the entry pins
# must equal the board's (4th field, as process_chip_sku_version reads it), and
# the board's ramcode must be in the entry's mem BCT group. <variants> lines:
# key|chipsku|ramcode (the variant's tegraflash --ramcode, empty if none), in
# signedFirmware's directory order.
rcm_select_variant() {
  local variants=$1 chkbdinfo=$2 uidlog=$3 cvm=$4 chipinfo=$5
  local ecid idval_1 idval_2 flval fuse chiprev boardid fab boardsku boardrev chipsku ramcode group spec
  local key vchipsku vramcode i
  local -a board_fields key_fields

  ecid=$(grep BR_CID "$uidlog" | cut -d' ' -f2)
  if [[ -z $ecid ]]; then
    echo "No BR_CID in $uidlog" >&2
    return 1
  fi
  idval_1="0x${ecid:3:2}"
  idval_2="0x${ecid:6:2}"
  case $idval_2 in
  0x23)
    flval=$(printf %x "$((0x${ecid:2:1} & 0x8))")$(printf %2.2x "$((idval_1 & 0xf0))")
    case $flval in
    000) fuse=0 ;;
    800 | 810 | 820 | 830 | 840 | 850 | 890 | 8a0 | 8b0 | 8c0 | 8d0) fuse=1 ;;
    *) flval= ;;
    esac
    ;;
  0x26)
    flval=$(printf %x "$((0x${ecid:2:1} & 0xe))")$(printf %2.2x "$((idval_1 & 0xf0))")
    case $flval in
    000) fuse=0 ;;
    800 | a00 | e00 | a80 | e80) fuse=1 ;;
    *) flval= ;;
    esac
    ;;
  *)
    echo "Unsupported chip ${idval_2} in BR_CID ${ecid}" >&2
    return 1
    ;;
  esac
  if [[ -z $flval ]]; then
    echo "Invalid fuse configuration in BR_CID ${ecid}" >&2
    return 1
  fi
  chiprev=${ecid:5:1}

  boardid=$(_rcm_bd "$chkbdinfo" -i "$cvm") && fab=$(_rcm_bd "$chkbdinfo" -f "$cvm") &&
    boardsku=$(_rcm_bd "$chkbdinfo" -k "$cvm") && boardrev=$(_rcm_bd "$chkbdinfo" -r "$cvm") &&
    chipsku=$(_rcm_bd "$chkbdinfo" -C "$chipinfo") && ramcode=$(_rcm_bd "$chkbdinfo" -R "$chipinfo") || return 1
  ramcode=$((16#$(cut -d: -f4 <<<"$ramcode") % 16))

  spec=$(generate_compat_spec "$boardid-$fab-$boardsku-$boardrev-$fuse-$chiprev") || {
    echo "$spec" >&2
    return 1
  }
  echo "Board: BOARDID=$boardid FAB=$fab BOARDSKU=$boardsku BOARDREV=$boardrev fuselevel=$fuse" \
    "chiprev=$chiprev CHIP_SKU=$chipsku RAMCODE=$ramcode, compat spec $spec" >&2

  IFS=- read -r -a board_fields <<<"$spec"
  while IFS='|' read -r key vchipsku vramcode; do
    IFS=- read -r -a key_fields <<<"$key"
    for i in 0 1 2 3 4 5; do
      if [[ -n ${board_fields[i]-} && -n ${key_fields[i]-} && ${board_fields[i]} != "${key_fields[i]}" ]]; then continue 2; fi
    done
    # Exact, not what the conf selects from it: update_flash_args reads chip_SKU
    # too, so the selection can't be checked outside flash.sh.
    if [[ -n $vchipsku && $(cut -d: -f4 <<<"$vchipsku") != "$(cut -d: -f4 <<<"$chipsku")" ]]; then
      echo "Variant $key is for chip SKU $vchipsku, the board has $chipsku" >&2
      return 1
    fi
    # The variant's RCM bundle has the mem BCT of its ramcode's group
    # (read_ramcode.func; tegraflash takes 0 without one).
    if [[ $idval_2 = 0x23 ]]; then group=4; else group=2; fi
    if ((${vramcode:-0} / group != ramcode / group)); then
      echo "Variant $key is for RAMCODE ${vramcode:-0}, the board has $ramcode" >&2
      return 1
    fi
    echo "Variant: $key" >&2
    echo "$key"
    return 0
  done <"$variants"
  echo "No firmware.variants entry matches $spec; this configuration has:" >&2
  cut -d'|' -f1 "$variants" >&2
  return 1
}
