{ lib
, stdenv
, buildPackages
, fetchFromGitHub
, fetchpatch
, fetchpatch2
, runCommand
, edk2
, acpica-tools
, dtc
, python3
, bc
, imagemagick
, unixtools
, libuuid
, applyPatches
, nukeReferences
, l4tVersion
, # Optional path to a boot logo that will be converted and cropped into the format required
  bootLogo ? null
, # Patches to apply to edk2-nvidia source tree
  edk2NvidiaPatches ? [ ]
, # Patches to apply to edk2 source tree
  edk2UefiPatches ? [ ]
, debugMode ? false
, errorLevelInfo ? debugMode
, # Enables a bunch more info messages

  # The root certificate (in PEM format) for authenticating capsule updates. By
  # default, EDK2 authenticates using a test keypair commited upstream.
  trustedPublicCertPemFile ? null
,
}:

let
  # TODO: Move this generation out of uefi-firmware.nix, because this .nix
  # file is callPackage'd using an aarch64 version of nixpkgs, and we don't
  # want to have to recompilie imagemagick
  bootLogoVariants = runCommand "uefi-bootlogo" { nativeBuildInputs = [ buildPackages.buildPackages.imagemagick ]; } ''
    mkdir -p $out
    convert ${bootLogo} -resize 1920x1080 -gravity Center -extent 1920x1080 -format bmp -define bmp:format=bmp3 $out/logo1080.bmp
    convert ${bootLogo} -resize 1280x720  -gravity Center -extent 1280x720  -format bmp -define bmp:format=bmp3 $out/logo720.bmp
    convert ${bootLogo} -resize 640x480   -gravity Center -extent 640x480   -format bmp -define bmp:format=bmp3 $out/logo480.bmp
  '';

  ###

  # See: https://github.com/NVIDIA/edk2-edkrepo-manifest/blob/main/edk2-nvidia/Jetson/NVIDIAJetsonManifest.xml
  edk2-src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2";
    rev = "r${l4tVersion}-edk2-stable202208";
    fetchSubmodules = true;
    sha256 = "sha256-PTbNxbncfSvxLW2XmdRHzUy+w5+1Blpk62DJpxDmedA=";
  };

  edk2-platforms = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-platforms";
    rev = "r${l4tVersion}-upstream-20220830";
    sha256 = "sha256-PjAJEbbswOLYupMg/xEqkAOJuAC8SxNsQlb9YBswRfo=";
  };

  edk2-non-osi = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-non-osi";
    rev = "r${l4tVersion}-upstream-20220830";
    sha256 = "sha256-EPtI63jYhEIo4uVTH3lUt9NC/lK5vPVacUAc5qgmz9M=";
  };

  edk2-nvidia = applyPatches {
    src = fetchFromGitHub {
      owner = "NVIDIA";
      repo = "edk2-nvidia";
      rev = "2c81e0fc74f703012dd3b2f18da5be256e142fe3"; # Latest on r35.3.1-updates as of 2023-05-17
      sha256 = "sha256-Qh1g+8a7ZcFG4VmwH+xDix6dpZ881HaNRE/FJoaRljw=";
    };
    patches = edk2NvidiaPatches ++ [
      (fetchpatch {
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
  };

  edk2-nvidia-non-osi = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-nvidia-non-osi";
    rev = "r${l4tVersion}";
    sha256 = "sha256-27PTl+svZUocmU6r/8FdqqI9rwHAi+6zSFs4fBA13Ks=";
  };

  # Patches from upstream tianocore/edk2 for OpenSSL, to enable in-tree build
  # of OpenSSL 1.1.1t
  opensslPatches = import ./edk2-openssl-patches.nix {
    inherit fetchpatch2;
  };

  # This has been taken from:
  # https://github.com/NixOS/nixpkgs/commit/3ed8d9b547c3941d74d9455fdec120f415ebaacd
  vendoredOpenSSL = fetchFromGitHub {
    owner = "openssl";
    repo = "openssl";
    rev = "OpenSSL_1_1_1t";
    sha256 = "sha256-gI2+Vm67j1+xLvzBb+DF0YFTOHW7myotRsXRzluzSLY=";
  };

  edk2-jetson = edk2.overrideAttrs (prev: {
    src = edk2-src;

    depsBuildBuild = prev.depsBuildBuild ++ [ libuuid ];

    patches =
      # Remove this one patch (CryptoPkg/OpensslLib: Upgrade OpenSSL to 1.1.1t)
      # present on nixos-23.05, as it will be added in the opensslPatches below
      (builtins.filter (patch: patch.url != "https://bugzilla.tianocore.org/attachment.cgi?id=1330") prev.patches)
      ++ opensslPatches;
    postUnpack = ''
      # This has been taken from:
      # https://github.com/NixOS/nixpkgs/commit/3ed8d9b547c3941d74d9455fdec120f415ebaacd
      rm -rf source/CryptoPkg/Library/OpensslLib/openssl
    '';
    postPatch = ''
      # This has been taken from:
      # https://github.com/NixOS/nixpkgs/commit/3ed8d9b547c3941d74d9455fdec120f415ebaacd

      # Replace the edk2's in-tree openssl git-submodule with our 1.1.1t
      cp -r ${vendoredOpenSSL} CryptoPkg/Library/OpensslLib/openssl
    '';
  });

  pythonEnv = buildPackages.python3.withPackages (ps: [ ps.tkinter ]);
  targetArch =
    if stdenv.isi686 then
      "IA32"
    else if stdenv.isx86_64 then
      "X64"
    else if stdenv.isAarch64 then
      "AARCH64"
    else
      throw "Unsupported architecture";

  buildType =
    if stdenv.isDarwin then
      "CLANGPDB"
    else
      "GCC5";

  buildTarget = if debugMode then "DEBUG" else "RELEASE";

  jetson-edk2-uefi =
    # TODO: edk2.mkDerivation doesn't have a way to override the edk version used!
    # Make it not via passthru ?
    stdenv.mkDerivation {
      pname = "jetson-edk2-uefi";
      version = l4tVersion;

      # Initialize the build dir with the build tools from edk2
      src = edk2-src;

      depsBuildBuild = [ buildPackages.stdenv.cc ];
      nativeBuildInputs = [ bc pythonEnv acpica-tools dtc unixtools.whereis ];
      strictDeps = true;

      NIX_CFLAGS_COMPILE = [
        "-Wno-error=format-security" # TODO: Fix underlying issue

        # Workaround for ../Silicon/NVIDIA/Drivers/EqosDeviceDxe/nvethernetrm/osi/core/osi_hal.c:1428: undefined reference to `__aarch64_ldadd4_sync'
        "-mno-outline-atomics"
      ];

      ${"GCC5_${targetArch}_PREFIX"} = stdenv.cc.targetPrefix;

      # From edk2-nvidia/Silicon/NVIDIA/edk2nv/stuart/settings.py
      PACKAGES_PATH = lib.concatStringsSep ":" [
        "${edk2-src}/BaseTools" # TODO: Is this needed?
        edk2-src
        edk2-platforms
        edk2-non-osi
        edk2-nvidia
        edk2-nvidia-non-osi
        "${edk2-platforms}/Features/Intel/OutOfBandManagement"
      ];

      enableParallelBuilding = true;

      postUnpack = ''
        # This has been taken from:
        # https://github.com/NixOS/nixpkgs/commit/3ed8d9b547c3941d74d9455fdec120f415ebaacd
        rm -rf source/CryptoPkg/Library/OpensslLib/openssl
      '';

      prePatch = ''
        rm -rf BaseTools
        cp -r ${edk2-jetson}/BaseTools BaseTools
        chmod -R u+w BaseTools
      '';

      patches = opensslPatches ++ edk2UefiPatches;

      postPatch = ''
        # This has been taken from:
        # https://github.com/NixOS/nixpkgs/commit/3ed8d9b547c3941d74d9455fdec120f415ebaacd

        # Replace the edk2's in-tree openssl git-submodule with our 1.1.1t
        cp -r ${vendoredOpenSSL} CryptoPkg/Library/OpensslLib/openssl
      '';

      configurePhase = ''
        runHook preConfigure
        export WORKSPACE="$PWD"
        source ./edksetup.sh BaseTools

        ${lib.optionalString (trustedPublicCertPemFile != null) ''
        echo Using ${trustedPublicCertPemFile} as public certificate for capsule verification
        ${lib.getExe buildPackages.openssl} x509 -outform DER -in ${trustedPublicCertPemFile} -out PublicCapsuleKey.cer
        python3 BaseTools/Scripts/BinToPcd.py -p gEfiSecurityPkgTokenSpaceGuid.PcdPkcs7CertBuffer -i PublicCapsuleKey.cer -o PublicCapsuleKey.cer.gEfiSecurityPkgTokenSpaceGuid.PcdPkcs7CertBuffer.inc
        python3 BaseTools/Scripts/BinToPcd.py -x -p gFmpDevicePkgTokenSpaceGuid.PcdFmpDevicePkcs7CertBufferXdr -i PublicCapsuleKey.cer -o PublicCapsuleKey.cer.gFmpDevicePkgTokenSpaceGuid.PcdFmpDevicePkcs7CertBufferXdr.inc
        ''}

        runHook postConfigure
      '';

      buildPhase = ''
        runHook preBuild

        # The BUILDID_STRING and BUILD_DATE_TIME are used
        # just by nvidia, not generic edk2
        build -a ${targetArch} -b ${buildTarget} -t ${buildType} -p Platform/NVIDIA/Jetson/Jetson.dsc -n $NIX_BUILD_CORES \
          -D BUILDID_STRING=${l4tVersion} \
          -D BUILD_DATE_TIME="$(date --utc --iso-8601=seconds --date=@$SOURCE_DATE_EPOCH)" \
          ${lib.optionalString (trustedPublicCertPemFile != null) "-D CUSTOM_CAPSULE_CERT"} \
          $buildFlags

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mv -v Build/*/* $out
        runHook postInstall
      '';
    };

  uefi-firmware = runCommand "uefi-firmware-${l4tVersion}"
    {
      nativeBuildInputs = [ python3 nukeReferences ];
    } ''
    mkdir -p $out
    python3 ${edk2-nvidia}/Silicon/NVIDIA/Tools/FormatUefiBinary.py \
      ${jetson-edk2-uefi}/FV/UEFI_NS.Fv \
      $out/uefi_jetson.bin

    python3 ${edk2-nvidia}/Silicon/NVIDIA/Tools/FormatUefiBinary.py \
      ${jetson-edk2-uefi}/AARCH64/L4TLauncher.efi \
      $out/L4TLauncher.efi

    mkdir -p $out/dtbs
    for filename in ${jetson-edk2-uefi}/AARCH64/Silicon/NVIDIA/Tegra/DeviceTree/DeviceTree/OUTPUT/*.dtb; do
      cp $filename $out/dtbs/$(basename "$filename" ".dtb").dtbo
    done

    # Get rid of any string references to source(s)
    nuke-refs $out/uefi_jetson.bin
  '';
in
{
  inherit edk2-jetson uefi-firmware;
}
