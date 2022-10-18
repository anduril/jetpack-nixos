{ lib, writeShellScriptBin, flash-tools, fetchurl, runtimeShell,

  name ? "generic", flashArgs ? null, postPatch ? "", partitionTemplate ? null,

  # Optional path to a boot logo that will be converted and cropped into the format required
  # The default logo is made available under a CC-BY license. See the repo for details.
  bootLogo ? (fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/e7d4050f2bb39a8c73a31a89e3d55f55536541c3/logo/nixos.svg";
    sha256 = "sha256-E+qpO9SSN44xG5qMEZxBAvO/COPygmn8r50HhgCRDSw=";
  }),

  # Optional directory containing DTBs to be used by flashing script, which can
  # be used by the bootloader(s) and passed to the kernel.
  dtbsDir ? null,

  # Optional package containing uefi_jetson.efi to replace prebuilt version
  jetson-firmware ? null,
}:

let
  _flash-tools = flash-tools.overrideAttrs (origAttrs: { postPatch = (origAttrs.postPatch or "") + postPatch; });
in writeShellScriptBin "flash-${name}" (''
  set -euo pipefail

  WORKDIR=$(mktemp -d)
  function on_exit() {
    rm -rf "$WORKDIR"
  }
  trap on_exit EXIT

  cp -r ${_flash-tools}/. "$WORKDIR"
  chmod -R u+w "$WORKDIR"
  cd "$WORKDIR"

  # Make nvidia's flash script happy by adding all this stuff to our PATH
  export PATH=${lib.makeBinPath _flash-tools.flashDeps}:$PATH

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
  ./flash.sh ${lib.optionalString (partitionTemplate != null) "-c flash.xml"} $@ ${flashArgs}
'' else ''
  ${runtimeShell}
''))
