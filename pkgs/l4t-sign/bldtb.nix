{ lib }:

# The bootloader DTB tegraflash concatenates onto UEFI (cpu-bootloader), and on
# r36 T234 also onto the dce blob: the kernel DTB with --odmdata patched into
# /chosen/odm-data, then each overlay appended at a 4 KiB boundary, then a 4 KiB
# pad and 64 zero bytes. Both inputs besides the DTB come from baseColdboot's
# overlaySet. $out/<overlaySet's dtb> is byte-equal to NVIDIA's
# `<stem>_with_odm_overlay.dtb.updated` (T234) / `<dtb>.updated` (T264).
# The appends themselves are plain `cat`: cpubl = UEFI ++ this; dce = dce blob
# ++ (r36: this, r39: the raw kernel DTB).
{
  # Package set to build with.
  pkgs
, # pyfdt comes from it; default: pkgs.pkgsBuildBuild's unpatched SDK flash-tools.
  flash-tools ? pkgs.pkgsBuildBuild.nvidia-jetpack.flash-tools
, name ? "bldtb"
, # DTB directory as flash.sh gets it in kernel/dtb (hardware.deviceTree.package).
  dtb
, # Directory: `dtb` = tegraflash's --bldtb basename, `order` = its --overlay_dtb
  # value, `odmdata` = its --odmdata value (missing or empty: none, as on T264),
  # and the .dtbo files named in `order` (flash.sh's mutated copies).
  overlaySet
}:

pkgs.runCommand name { } ''
  export PATH=${lib.makeBinPath flash-tools.flashDeps}:$PATH
  export PYTHONPATH=${flash-tools}/bootloader/pyfdt PYTHONDONTWRITEBYTECODE=1
  mkdir $out
  python3 ${./bldtb.py} ${lib.optionalString (lib.versionAtLeast flash-tools.version "38") "--drop-del"} \
    $out ${dtb} ${overlaySet}
''
