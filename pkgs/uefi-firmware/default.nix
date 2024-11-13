{ stdenv
, runCommand
, callPackages
, acpica-tools
, python3
, nukeReferences
, l4tVersion
, debugMode ? false
, ...
}:
#
# Note:
#
# Adjust following check when target/platform is tested!
#
if l4tVersion != "36.3.0" then
  throw "Only tested with l4tVersion 36.3.0"
else

let
  targetArch =
    if stdenv.isAarch64 then
      "AARCH64"
    else
      throw "Only supported target architecture is AARCH64";

  buildType =
    if stdenv.isLinux then
      "GCC5"
    else
      throw "Only supported build platform is Linux/GCC";

  buildTarget =
    if debugMode then
      "DEBUG"
    else
      "RELEASE";

  edk2 = callPackages ./edk2 {inherit l4tVersion targetArch buildType buildTarget;};
in
  runCommand "uefi-firmware-${l4tVersion}"
    {
      nativeBuildInputs = [ python3 nukeReferences ];
    } ''
    mkdir -p $out
    python3 ${edk2.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
      ${edk2.jetson-edk2-uefi}/FV/UEFI_NS.Fv \
      $out/uefi_jetson.bin

    python3 ${edk2.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
      ${edk2.jetson-edk2-uefi}/AARCH64/L4TLauncher.efi \
      $out/L4TLauncher.efi

    mkdir -p $out/dtbs
    for filename in ${edk2.jetson-edk2-uefi}/AARCH64/Silicon/NVIDIA/Tegra/DeviceTree/DeviceTree/OUTPUT/*.dtb; do
      cp $filename $out/dtbs/$(basename "$filename" ".dtb").dtbo
    done

    # Get rid of any string references to source(s)
    nuke-refs $out/uefi_jetson.bin
  ''

