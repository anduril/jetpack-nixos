{ lib
, runCommand
, fetchpatch
, fetchFromGitHub
, imagemagick
, applyPatches
, l4tVersion
, errorLevelInfo ? false
, bootLogo ? null # Optional path to a boot logo that will be converted and cropped into the format required
}:

let
  bootLogoVariants = runCommand "uefi-bootlogo" { nativeBuildInputs = [ imagemagick ]; } ''
    mkdir -p $out
    convert ${bootLogo} -resize 1920x1080 -gravity Center -extent 1920x1080 -format bmp -define bmp:format=bmp3 $out/logo1080.bmp
    convert ${bootLogo} -resize 1280x720  -gravity Center -extent 1280x720  -format bmp -define bmp:format=bmp3 $out/logo720.bmp
    convert ${bootLogo} -resize 640x480   -gravity Center -extent 640x480   -format bmp -define bmp:format=bmp3 $out/logo480.bmp
  '';
in
applyPatches {
  name = "edk2-nvidia";

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-nvidia";
    rev = "c101ba515b2737fb78d8929c2852f5c8f9607330"; # Latest on r${l4tVersion}-updates branch as of 2024-01-15
    sha256 = "sha256-Ofj1FS1wLTLf6rCCPbB841SSBM3wjW4tdUJD6cY0ixE=";
  };

  patches = [
    # Fix Eqos driver to use correct TX clock name
    # PR: https://github.com/NVIDIA/edk2-nvidia/pull/76
    (fetchpatch {
      url = "https://github.com/NVIDIA/edk2-nvidia/commit/26f50dc3f0f041d20352d1656851c77f43c7238e.patch";
      hash = "sha256-cc+eGLFHZ6JQQix1VWe/UOkGunAzPb8jM9SXa9ScIn8=";
    })

    ./capsule-authentication.patch

    # Have UEFI use the device tree compiled into the firmware, instead of
    # using one from the kernel-dtb partition.
    # See: https://github.com/anduril/jetpack-nixos/pull/18
    ./edk2-uefi-dtb.patch

    # Include patches to fix "Assertion 3" mentioned here:
    # https://forums.developer.nvidia.com/t/assertion-issue-in-uefi-during-boot/315628
    # From this PR: https://github.com/NVIDIA/edk2-nvidia/pull/110
    # It is unclear if it does (as of 2025-01-03), but hopefully this also
    # resolves the critical issue mentioned here:
    # https://forums.developer.nvidia.com/t/possible-uefi-memory-leak-and-partition-full/308540
    ./fix-bug-in-block-erase-logic.patch
    ./fix-variant-read-records-per-erase-block-and-fix-leak.patch
  ];

  postPatch = lib.optionalString errorLevelInfo ''
    sed -i 's#PcdDebugPrintErrorLevel|.*#PcdDebugPrintErrorLevel|0x8000004F#' Platform/NVIDIA/NVIDIA.common.dsc.inc
  '' + lib.optionalString (bootLogo != null) ''
    cp ${bootLogoVariants}/logo1080.bmp Silicon/NVIDIA/Assets/nvidiagray1080.bmp
    cp ${bootLogoVariants}/logo720.bmp Silicon/NVIDIA/Assets/nvidiagray720.bmp
    cp ${bootLogoVariants}/logo480.bmp Silicon/NVIDIA/Assets/nvidiagray480.bmp
  '';
}
