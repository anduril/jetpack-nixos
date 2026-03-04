# See also: nvidia-l4t-init/opt/nvidia/nv-l4t-bootloader-config.sh
# and meta-tegra recipes-bsp/tools/setup-nv-boot-control

generate_compat_spec() {
  local boardspec=$1
  local boardid=$(echo "$boardspec" | cut -d- -f1)
  local fab=$(echo "$boardspec" | cut -d- -f2)
  local boardsku=$(echo "$boardspec" | cut -d- -f3)
  local boardrev=$(echo "$boardspec" | cut -d- -f4)
  local fuselevel=$(echo "$boardspec" | cut -d- -f5)
  local chiprev=$(echo "$boardspec" | cut -d- -f6)

  case "${boardid}" in
  # Xavier AGX
  2888)
    if [[ "${boardsku}" == "0004" ]]; then
      boardrev=""
      fab="400"
    elif [[ "${fab}" == "400" ]]; then
      if [[ "${boardrev}" == "D.0" || "${boardrev}" < "D.0" ]]; then
        boardrev="D.0"
      else
        boardrev="E.0"
      fi
      boardsku="0001"
    elif [[ "${fab}" == "600" ]]; then
      if [[ "${boardsku}" == "0008" ]]; then
        boardrev=""
      fi
    fi
    ;;

  # Xavier NX
  3668)
    if [[ "${fab}" != "301" ]]; then
      fab="100"
    fi
    boardsku=""
    boardrev=""
    chiprev=""
    ;;

  # Orin AGX
  3701)
    if [[ "${boardsku}" == "0000" ]]; then
      if [[ "${fab}" == "0"* ]] || [[ "${fab}" == "1"* ]] || [[ "${fab}" == "2"* ]] || [[ "${fab}" == "TS"* ]] || [[ "${fab}" == "EB"* ]]; then
        fab="000"
      else
        fab="300"
      fi
    fi
    if [[ "${boardsku}" == "0004" ]] || [[ "${boardsku}" == "0005" ]] || [[ "${boardsku}" == "0008" ]]; then
      fab=""
    fi
    boardrev=""
    chiprev=""
    ;;

  # Orin NX/Nano
  3767)
    if [[ "${boardsku}" == "0000" ]] || [[ "${boardsku}" == "0002" ]]; then
      if [[ "${fab}" != "TS"* ]] && [[ "${fab}" != "EB"* ]]; then
        fab="000"
      fi
    else
      fab=""
    fi
    boardrev=""
    chiprev=""
    ;;

  # Thor AGX
  3834)
    if [[ "${boardsku}" == "0008" ]]; then
      if [[ "${fab}" -gt 400 ]]; then
        fab="400"
      else
        fab="000"
      fi
    else
      fab=""
    fi
    boardsku=""
    boardrev=""
    chiprev=""
    ;;

  *)
    echo "Unknown boardid: ${boardid}"
    exit 1
    ;;
  esac

  echo "$boardid-$fab-$boardsku-$boardrev-$fuselevel-$chiprev"
}

noRuntimeUefiWrites=
espDir=
detect_can_write_runtime_uefi_vars() {
  local boardspec=$1

  # All AGX Xaviers except industrial variants have firmware on emmc instead of qspi
  boardid=$(echo "$boardspec" | cut -d- -f1)
  boardsku=$(echo "$boardspec" | cut -d- -f3)
  noRuntimeUefiWrites=
  if [[ "$boardid" == "2888" ]] && [[ "$boardsku" != "0008" ]]; then
    noRuntimeUefiWrites=true
    espDir=/opt/nvidia/esp
  else
    espDir=@efiSysMountPoint@
  fi
}

# Call detect_can_write_runtime_uefi_vars before running this
set_efi_var() {
  local name=$1
  local value=$2

  local filepath

  if [[ -n "$noRuntimeUefiWrites" ]]; then
    if ! mountpoint -q "$espDir"; then
      echo "$espDir is not mounted. Unable to set EFI variable."
      exit 1
    fi

    mkdir -p "$espDir"/EFI/NVDA/Variables
    filepath="$espDir"/EFI/NVDA/Variables/"$name"

    echo "NOTE: A reboot is required for the configuration update to complete"
  else
    filepath=/sys/firmware/efi/efivars/"$name"

    if [[ -e "$filepath" ]]; then
      chattr -i "$filepath"
    fi
  fi

  printf "$value" >$filepath
}

# Call detect_can_write_runtime_uefi_vars before running this
rm_efi_var() {
  local name=$1

  local filepath

  if [[ -n "$noRuntimeUefiWrites" ]]; then
    if ! mountpoint -q "$espDir"; then
      echo "$espDir is not mounted. Unable to remove EFI variable."
      exit 1
    fi

    mkdir -p "$espDir"/EFI/NVDA/Variables
    filepath="$espDir"/EFI/NVDA/Variables/"$name"

    printf "\x07\x00\x00\x00" >"$filepath"

    echo "NOTE: A reboot is required for the configuration update to complete"
  else
    filepath=/sys/firmware/efi/efivars/"$name"

    if [[ -e "$filepath" ]]; then
      chattr -i "$filepath"
      rm "$filepath"
    fi
  fi
}

get_efi_str() {
  local variable=$1
  local p="/sys/firmware/efi/efivars/$variable"

  # If we don't support runtime variable writes and we've written
  # to the variable, report the pending value
  if [[ -n "$noRuntimeUefiWrites" ]]; then
    filepath="$espDir"/EFI/NVDA/Variables/"$variable"
    if mountpoint -q "$espDir" && [[ -e "$filepath" ]]; then
      p="$filepath"
    fi
  fi

  # TODO: if the UEFI variable is an empty string, that's equivalent to
  # deleting it. Relevant in cases where runtime UEFI variable writes aren't
  # supported. In this case, we might want to report "Variable Doesn't Exist".
  if [ -f "$p" ]; then
    dd "if=$p" iseek=4 ibs=1 status=none
  else
    echo "Variable Doesn't Exist"
  fi
}

get_efi_int() {
  local variable=$1
  local width=${2:-4}
  local p="/sys/firmware/efi/efivars/$variable"

  # If we don't support runtime variable writes and we've written
  # to the variable, report the pending value
  if [[ -n "$noRuntimeUefiWrites" ]]; then
    filepath="$espDir"/EFI/NVDA/Variables/"$variable"
    if mountpoint -q "$espDir" && [[ -e "$filepath" ]]; then
      p="$filepath"
    fi
  fi

  # TODO: see comment in get_efi_str
  if [ -f "$p" ]; then
    printf "%u" "$(od --skip-bytes=4 --address-radix=none "--format=u${width}" "$p")"
  else
    echo "Variable Doesn't Exist"
  fi
}
