#!/usr/bin/env bash

source "@ota_helpers@"
boardspec=$(tegra-boardspec)
detect_can_write_runtime_uefi_vars "$boardspec"

declare -A slot
slot["0"]="A"
slot["1"]="B"

# https://github.com/NVIDIA/edk2-nvidia/blob/main/Silicon/NVIDIA/Drivers/BootChainDxe/BootChainDxePrivate.h
declare -A bootchainstatus
bootchainstatus["0"]="STATUS_SUCCESS"
bootchainstatus["1"]="STATUS_IN_PROGRESS"
bootchainstatus["2"]="STATUS_ERROR_NO_OPERATION_REQUIRED"
bootchainstatus["3"]="STATUS_ERROR_CANCELED_FOR_FMP_CONFLICT"
bootchainstatus["4"]="STATUS_ERROR_READING_STATUS"
bootchainstatus["5"]="STATUS_ERROR_MAX_RESET_COUNT"
bootchainstatus["6"]="STATUS_ERROR_SETTING_RESET_COUNT"
bootchainstatus["7"]="STATUS_ERROR_SETTING_IN_PROGRESS"
bootchainstatus["8"]="STATUS_ERROR_IN_PROGRESS_FAILED"
bootchainstatus["9"]="STATUS_ERROR_BAD_BOOT_CHAIN_NEXT"
bootchainstatus["10"]="STATUS_ERROR_READING_NEXT"
bootchainstatus["11"]="STATUS_ERROR_UPDATING_FW_CHAIN"
bootchainstatus["12"]="STATUS_ERROR_BOOT_CHAIN_FAILED"
bootchainstatus["13"]="STATUS_ERROR_READING_RESET_COUNT"
bootchainstatus["14"]="STATUS_ERROR_BOOT_NEXT_EXISTS"
bootchainstatus["15"]="STATUS_ERROR_READING_SCRATCH"
bootchainstatus["16"]="STATUS_ERROR_SETTING_SCRATCH"
bootchainstatus["17"]="STATUS_ERROR_UPDATE_BR_BCT_FLAG_SET"
bootchainstatus["18"]="STATUS_ERROR_SETTING_PREVIOUS"
bootchainstatus["19"]="STATUS_ERROR_BOOT_CHAIN_IS_FAILED"

declare -A esrtstatus
# https://github.com/tianocore/edk2/blob/master/MdePkg/Include/Guid/SystemResourceTable.h
esrtstatus["0"]="SUCCESS"
esrtstatus["1"]="ERROR_UNSUCCESSFUL"
esrtstatus["2"]="ERROR_INSUFFICIENT_RESOURCES"
esrtstatus["3"]="ERROR_INCORRECT_VERSION"
esrtstatus["4"]="ERROR_INVALID_FORMAT"
esrtstatus["5"]="ERROR_AUTH_ERROR"
esrtstatus["6"]="ERROR_PWR_EVT_AC"
esrtstatus["7"]="ERROR_PWR_EVT_BATT"
esrtstatus["8"]="ERROR_UNSATISFIED_DEPENDENCIES"
# https://github.com/NVIDIA/edk2-nvidia/blob/main/Silicon/NVIDIA/Library/FmpDeviceLib/TegraFmp.c
esrtstatus["6144"]="BAD_IMAGE_POINTER"
esrtstatus["6145"]="INVALID_PACKAGE_HEADER"
esrtstatus["6146"]="UNSUPPORTED_PACKAGE_TYPE"
esrtstatus["6147"]="INVALID_PACKAGE_IMAGE_INFO_ARRAY"
esrtstatus["6148"]="IMAGE_TOO_BIG"
esrtstatus["6149"]="PACKAGE_SIZE_ERROR"
esrtstatus["6150"]="NOT_UPDATABLE"
esrtstatus["6151"]="IMAGE_NOT_IN_PACKAGE"
esrtstatus["6152"]="MB1_INVALIDATE_ERROR"
esrtstatus["6153"]="SINGLE_IMAGE_NOT_SUPPORTED"
esrtstatus["6154"]="IMAGE_INDEX_MISSING"
esrtstatus["6155"]="NO_PROTOCOL_FOR_IMAGE"
esrtstatus["6156"]="IMAGE_ATTRIBUTES_ERROR"
esrtstatus["6157"]="BCT_UPDATE_FAILED"
esrtstatus["6158"]="WRITE_IMAGES_FAILED"
esrtstatus["6169"]="MB1_WRITE_ERROR"
esrtstatus["6160"]="VERIFY_IMAGES_FAILED"
esrtstatus["6161"]="SET_SINGLE_IMAGE_FAILED"
esrtstatus["6162"]="FMP_LIB_UNINITIALIZED"
esrtstatus["6163"]="BOOT_CHAIN_UPDATE_CANCELED"
esrtstatus["6164"]="GPT_METADATA_UPDATE_FAILED"
esrtstatus["6165"]="GPT_VERIFY_FAILED"
esrtstatus["6166"]="GPT_INVALIDATE_FAILED"
esrtstatus["6167"]="GPT_WRITE_FAILED"
esrtstatus["6168"]="SET_INACTIVE_BOOT_CHAIN_BAD_FAILED"
esrtstatus["6169"]="SET_INACTIVE_BOOT_CHAIN_GOOD_FAILED"
esrtstatus["6170"]="UPDATE_BCT_BACKUP_PARTITION_FAILED"

# https://github.com/tianocore/edk2/blob/master/MdePkg/Include/Guid/SystemResourceTable.h
declare -A esrttype
esrttype["0"]="ESRT_FW_TYPE_UNKNOWN"
esrttype["1"]="ESRT_FW_TYPE_SYSTEMFIRMWARE"
esrttype["2"]="ESRT_FW_TYPE_DEVICEFIRMWARE"
esrttype["3"]="ESRT_FW_TYPE_UEFIDRIVER"

get_esrt() {
  local variable=$1
  local p="/sys/firmware/efi/esrt/entries/entry0/$variable"

  if [ -f "$p" ]; then
    cat "$p"
  else
    echo "Variable Doesn't Exist"
  fi
}

get_esrt_version() {
  local hex_version

  hex_version=$(printf "%06x" "$(get_esrt "$@")")

  printf "%d.%d.%d" "0x${hex_version:0:2}" "0x${hex_version:2:2}" "0x${hex_version:4:2}"
}

lookup() {
  local value="$1"
  local -n array="$2"

  if [[ -v array["$value"] ]]; then
    echo "${array["$value"]}"
  else
    echo "$value"
  fi
}

show_help() {
  echo "$* - Check Jetson firmware status"
  echo
  echo "-h      show this message"
  echo "-b      show only brief output: current and expected firmware versions"
}

brief=

while getopts ":hb" opt ; do
  case $opt in
    h)
      show_help
      exit 0
      ;;
    b)
      brief=1
      ;;
    ?)
      echo "Error: invalid option -$OPTARG" >&2
      show_help "$@" >&2
      exit 2\
      ;;
    *)
      echo "Unknown error" >&2
      show_help "$@" >&2
      exit 2
      ;;
  esac
done

CURRENT_FW_VER=$(cat /sys/devices/virtual/dmi/id/bios_version || echo Unknown)
EXPECTED_FW_VER=@expectedBiosVersion@

if [ -z "$brief" ]; then
  echo "================================= Version Info ================================="
fi

echo "Current firmware version is : ${CURRENT_FW_VER}"
echo "Expected firmware version is: ${EXPECTED_FW_VER}"

if [ -z "$brief" ] ; then
  # Capsule update is pending if TEGRA_BL.Cap exists and
  # OsIndications bit 4 is set (EFI_OS_INDICATIONS_FILE_CAPSULE_DELIVERY_SUPPORTED)
  if ! mountpoint -q @efiSysMountPoint@; then
    UPDATE_PENDING="unknown (ESP not mounted)"
  elif [[ ! -r @efiSysMountPoint@ ]]; then
    UPDATE_PENDING="unknown (missing permissons)"
  elif [[ -d @efiSysMountPoint@/EFI/UpdateCapsule && -n "$(ls @efiSysMountPoint@/EFI/UpdateCapsule)" ]] &&
    [[ "$(get_efi_int OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c 8)" != "Variable Doesn't Exist" ]] &&
    (("$(get_efi_int OsIndications-8be4df61-93ca-11d2-aa0d-00e098032b8c 8)" & 4)); then
    UPDATE_PENDING=yes
  fi

  echo "TegraPlatformCompatSpec     : $(get_efi_str TegraPlatformCompatSpec-781e084c-a330-417c-b678-38e696380cb9)"
  echo "TegraPlatformSpec           : $(get_efi_str TegraPlatformSpec-781e084c-a330-417c-b678-38e696380cb9)"
  echo ""
  echo "=============================== Boot Chain Info ================================"
  echo "BootChainFwCurrent               : $(lookup "$(get_efi_int BootChainFwCurrent-781e084c-a330-417c-b678-38e696380cb9)" slot)"
  echo "BootChainFwNext                  : $(lookup "$(get_efi_int BootChainFwNext-781e084c-a330-417c-b678-38e696380cb9)" slot)"
  # Xavier AGX clears BootChainFwStatus upon reboot since it doesn't have runtime writable UEFI variables.
  # get_efi_int will give us the to-be-written value, which is functionally an empty string.
  # This isn't interesting or useful, so always grab the cached value in /var/run/tegra-bootchainfwstatus
  if [[ ( ! -e /var/run/tegra-bootchainfwstatus ) || ( -e /sys/firmware/efi/efivars/BootChainFwStatus-781e084c-a330-417c-b678-38e696380cb9 && -z "$noRuntimeUefiWrites" ) ]]; then
    echo "BootChainFwStatus                : $(lookup "$(get_efi_int BootChainFwStatus-781e084c-a330-417c-b678-38e696380cb9)" bootchainstatus)"
  else
    echo "BootChainFwStatus                : $(lookup "$(cat /var/run/tegra-bootchainfwstatus)" bootchainstatus)"
  fi
  echo "Capsule Update Pending           : ${UPDATE_PENDING:-no}"
  if [ "$EUID" -ne 0 ]; then
    echo ""
    echo "Please run as root for ESRT table info"
  else
    echo "ESRT capsule_flags               : $(get_esrt capsule_flags)"
    echo "ESRT fw_class                    : $(get_esrt fw_class)"
    echo "ESRT fw_type                     : $(lookup "$(get_esrt fw_type)" esrttype)"
    echo "ESRT fw_version                  : $(get_esrt_version fw_version)"
    echo "ESRT last_attempt_status         : $(lookup "$(get_esrt last_attempt_status)" esrtstatus)"
    echo "ESRT last_attempt_version        : $(get_esrt_version last_attempt_version)"
    echo "ESRT lowest_supported_fw_version : $(get_esrt_version lowest_supported_fw_version)"
  fi
fi

# Xavier AGX clears BootChainFwStatus upon reboot since it doesn't have runtime writable UEFI variables.
if [[ -e /sys/firmware/efi/efivars/BootChainFwStatus-781e084c-a330-417c-b678-38e696380cb9 && -n "$noRuntimeUefiWrites" ]]; then
  echo
  echo "A reboot is required before capsule updates can be installed."
fi

if [[ $CURRENT_FW_VER != "$EXPECTED_FW_VER" ]]; then
  exit 1
fi
