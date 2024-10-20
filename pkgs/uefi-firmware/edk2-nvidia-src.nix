{ lib
, runCommand
, fetchpatch
, fetchFromGitHub
, imagemagick
, applyPatches
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
    rev = "8444db349648a77ed8e2e3047a93004c9cadb2d3"; # Latest on r35.4.1-updates as of 2023-08-07
    sha256 = "sha256-jHyyg5Ywg/tQg39oY1EwHPBjUTE7r7C9q0HO1vqCL6s=";
  };

  patches = [
    (fetchpatch {
      # https://github.com/NVIDIA/edk2-nvidia/pull/68
      name = "fix-disabled-serial.patch";
      url = "https://github.com/NVIDIA/edk2-nvidia/commit/9604259b0d11c049f6a3eb5365a3ae10cfb9e6d9.patch";
      hash = "sha256-v/WEwcSNjBXeN0eXVzzl31dn6mq78wIm0u5lW1jGcdE=";
    })

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
  ];

  postPatch = lib.optionalString errorLevelInfo ''
    sed -i 's#PcdDebugPrintErrorLevel|.*#PcdDebugPrintErrorLevel|0x8000004F#' Platform/NVIDIA/NVIDIA.common.dsc.inc
  '' + lib.optionalString (bootLogo != null) ''
    cp ${bootLogoVariants}/logo1080.bmp Silicon/NVIDIA/Assets/nvidiagray1080.bmp
    cp ${bootLogoVariants}/logo720.bmp Silicon/NVIDIA/Assets/nvidiagray720.bmp
    cp ${bootLogoVariants}/logo480.bmp Silicon/NVIDIA/Assets/nvidiagray480.bmp
  '';
}
