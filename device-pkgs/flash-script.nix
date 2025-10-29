{ lib
, preFlashCommands ? ""
, flashCommands ? ""
, postFlashCommands ? ""
, flashArgs ? [ ]
, partitionTemplate ? null
, socType ? null
, # Optional directory containing DTBs to be used by flashing script, which can
  # be used by the bootloader(s) and passed to the kernel.
  dtbsDir ? null
, # Optional package containing uefi_jetson.efi to replace prebuilt version
  uefi-firmware ? null
, # Optional package containing tos.img to replace prebuilt version
  tosImage ? null
, # Optional EKS file containing encrypted keyblob
  eksFile ? null
, # Additional DTB overlays to use during device flashing
  additionalDtbOverlays ? [ ]
, flash-tools
}:
let
  uefi_image = if socType == "t264" then "uefi_t26x_general.bin" else "uefi_jetson.bin";
in
(''
  set -euo pipefail

  if [[ -z ''${WORKDIR-} ]]; then
    WORKDIR=$(mktemp -d)
    function on_exit() {
      rm -rf "$WORKDIR"
    }
    trap on_exit EXIT
  fi

  cp -r ${flash-tools}/. "$WORKDIR"
  chmod -R u+w "$WORKDIR"
  cd "$WORKDIR"

  # Make nvidia's flash script happy by adding all this stuff to our PATH
  export PATH=${lib.makeBinPath flash-tools.flashDeps}:$PATH

  export NO_ROOTFS=1
  export NO_RECOVERY_IMG=1
  export NO_ESP_IMG=1

  export ADDITIONAL_DTB_OVERLAY=''${ADDITIONAL_DTB_OVERLAY:+$ADDITIONAL_DTB_OVERLAY,}${lib.concatStringsSep "," additionalDtbOverlays}

  ${lib.optionalString (partitionTemplate != null) "cp ${partitionTemplate} flash.xml"}
  ${lib.optionalString (dtbsDir != null) "cp -r ${dtbsDir}/. kernel/dtb/"}
  ${lib.optionalString (uefi-firmware != null) ''
  cp ${uefi-firmware}/uefi_jetson.bin bootloader/${uefi_image}
  if [ -e "${uefi-firmware}/uefi_jetson_minimal.bin" ] ; then
    cp ${uefi-firmware}/uefi_jetson_minimal.bin bootloader/uefi_jetson_minimal.bin
  fi

  # For normal NixOS usage, we'd probably use systemd-boot or GRUB instead,
  # but lets replace the upstream L4TLauncher EFI payload anyway
  cp ${uefi-firmware}/L4TLauncher.efi bootloader/BOOTAA64.efi

  # Replace additional dtbos
  if [ -e ${uefi-firmware}/dtbs ]; then
    cp ${uefi-firmware}/dtbs/*.dtbo kernel/dtb/
  fi
  ''}
  ${lib.optionalString (tosImage != null) ''
  cp ${tosImage}/tos.img bootloader/tos-optee_${socType}.img
  if [ -e ${tosImage}/bl31.fip ]; then
    cp ${tosImage}/bl31.fip bootloader/bl31_${socType}.fip
  fi
  ''}
  ${lib.optionalString (eksFile != null) ''
  cp ${eksFile} bootloader/eks_${socType}.img
  ''}

  ${preFlashCommands}

  chmod -R u+w .

'' + (if (flashCommands != "") then ''
  ${flashCommands}
'' else ''
  ./flash.sh ${lib.optionalString (partitionTemplate != null) "-c flash.xml"} "$@" ${builtins.toString flashArgs}
'') + ''
  ${postFlashCommands}
'')
