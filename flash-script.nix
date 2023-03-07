{ lib, writeShellScriptBin, flash-tools, fetchurl, runtimeShell,

  name ? "generic", flashArgs ? null, partitionTemplate ? null,

  # Optional directory containing DTBs to be used by flashing script, which can
  # be used by the bootloader(s) and passed to the kernel.
  dtbsDir ? null,

  # Optional package containing uefi_jetson.efi to replace prebuilt version
  jetson-firmware ? null,
}:

writeShellScriptBin "flash-${name}" (''
  set -euo pipefail

  WORKDIR=$(mktemp -d)
  function on_exit() {
    rm -rf "$WORKDIR"
  }
  trap on_exit EXIT

  cp -r ${flash-tools}/. "$WORKDIR"
  chmod -R u+w "$WORKDIR"
  cd "$WORKDIR"

  # Make nvidia's flash script happy by adding all this stuff to our PATH
  export PATH=${lib.makeBinPath flash-tools.flashDeps}:$PATH

  export NO_ROOTFS=1
  export NO_RECOVERY_IMG=1

  ${lib.optionalString (partitionTemplate != null) "cp ${partitionTemplate} flash.xml"}
  ${lib.optionalString (dtbsDir != null) "cp -r ${dtbsDir}/. kernel/dtb/"}
  ${lib.optionalString (jetson-firmware != null) ''
  cp ${jetson-firmware}/uefi_jetson.bin bootloader/uefi_jetson.bin

  # For normal NixOS usage, we'd probably use systemd-boot or GRUB instead,
  # but lets replace the upstream L4TLauncher EFI payload anyway
  cp ${jetson-firmware}/L4TLauncher.efi bootloader/BOOTAA64.efi

  # Replace additional dtbos
  cp ${jetson-firmware}/dtbs/*.dtbo kernel/dtb/
  ''}

  chmod -R u+w .

'' + (if (flashArgs != null) then ''
  ./flash.sh ${lib.optionalString (partitionTemplate != null) "-c flash.xml"} $@ ${builtins.toString flashArgs}
'' else ''
  ${runtimeShell}
''))
