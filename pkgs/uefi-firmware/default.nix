{ runCommand
, python3
, nukeReferences
, l4tVersion
, edk2NvidiaSrc
, jetsonEdk2Uefi
}:

runCommand "uefi-firmware-${l4tVersion}"
{
  nativeBuildInputs = [ python3 nukeReferences ];
} ''
  mkdir -p $out
  python3 ${edk2NvidiaSrc}/Silicon/NVIDIA/Tools/FormatUefiBinary.py \
    ${jetsonEdk2Uefi}/FV/UEFI_NS.Fv \
    $out/uefi_jetson.bin

  python3 ${edk2NvidiaSrc}/Silicon/NVIDIA/Tools/FormatUefiBinary.py \
    ${jetsonEdk2Uefi}/AARCH64/L4TLauncher.efi \
    $out/L4TLauncher.efi

  mkdir -p $out/dtbs
  for filename in ${jetsonEdk2Uefi}/AARCH64/Silicon/NVIDIA/Tegra/DeviceTree/DeviceTree/OUTPUT/*.dtb; do
    cp $filename $out/dtbs/$(basename "$filename" ".dtb").dtbo
  done

  # Get rid of any string references to source(s)
  nuke-refs $out/uefi_jetson.bin
''
