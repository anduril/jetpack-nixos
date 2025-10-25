{ lib
, stdenv
, callPackage
, buildPackages
, fetchFromGitHub
, fetchpatch
, runCommand
, acpica-tools
, dtc
, python3
, unixtools
, libuuid
, which
, nasm
, applyPatches
, nukeReferences
, l4tMajorMinorPatchVersion
, uniqueHash ? ""
, # Optional path to a boot logo that will be converted and cropped into the format required
  bootLogo ? null
, # Patches to apply to edk2-nvidia source tree
  edk2NvidiaPatches ? [ ]
, # Patches to apply to edk2 source tree
  edk2UefiPatches ? [ ]
, debugMode ? false
, socFamily ? "t26x"
, defconfig ? "${socFamily}_general"
, errorLevelInfo ? debugMode
, # Enables a bunch more info messages

  # The root certificate (in PEM format) for authenticating capsule updates. By
  # default, EDK2 authenticates using a test keypair commited upstream.
  trustedPublicCertPemFile ? null
}:

let
  # TODO: Move this generation out of uefi-firmware.nix, because this .nix
  # file is callPackage'd using an aarch64 version of nixpkgs, and we don't
  # want to have to recompilie imagemagick
  bootLogoVariants = runCommand "uefi-bootlogo" { nativeBuildInputs = [ buildPackages.buildPackages.imagemagick ]; } ''
    mkdir -p "$out"
    convert "${bootLogo}" -resize 1920x1080 -gravity Center -extent 1920x1080 -format bmp -define bmp:format=bmp3 "$out/logo1080.bmp"
    convert "${bootLogo}" -resize 1280x720  -gravity Center -extent 1280x720  -format bmp -define bmp:format=bmp3 "$out/logo720.bmp"
    convert "${bootLogo}" -resize 640x480   -gravity Center -extent 640x480   -format bmp -define bmp:format=bmp3 "$out/logo480.bmp"
  '';

  # See: https://github.com/NVIDIA/edk2-edkrepo-manifest/blob/7b298576d93b0fae216aee7a1539268f4ce9c6a9/edk2-nvidia/Platform/NVIDIAPlatformsManifest.xml#L306
  defaultOrigin = {
    owner = "NVIDIA";
    rev = "r38.2";
  };
  repos = {
    edk2 = {
      sha256 = "sha256-qJoQrU9o9HYdT9xwXV4fqQqIpG7zvL1nAzE+6fuwRFk=";
      fetchSubmodules = true;
    };
    edk2-non-osi.sha256 = "sha256-Dj6Og/sc3MEMU/37rUMu7miHOvFi3Qvfkm+nMSUBUF0=";
    edk2-platforms.sha256 = "sha256-PsKxy/tiRl2/qcL/JQNXbUPsnWekAQ+4b+NiccSRGa4=";
    edk2-infineon.sha256 = "sha256-47UJfEd4ViTenx5dvy2G75NFSgmcsyIWpN0Lv1QlvA8=";
    edk2-redfish-client.sha256 = "sha256-EUWi5z+1sz2zMZM6x/sqE2NvdHRkQwQOcotsUwELsBY=";
    edk2-nvidia.sha256 = "sha256-G+WoeWH4OxQlpwUijHSr5fcgQxLbzrGlackIUSxWtFc=";
    edk2-nvidia-non-osi.sha256 = "sha256-8y7rNaaXC9ZvNHV/NRmbMVPCgYERqqley2SnMer5T0k=";
  };

  fetchRepo = name: value: fetchFromGitHub (defaultOrigin // { inherit name; repo = name; } // value);
  fetchedRepos = builtins.mapAttrs fetchRepo repos;

  patchedRepos = fetchedRepos // {
    edk2 = applyPatches {
      name = "edk2";
      src = fetchedRepos.edk2;
      # see https://github.com/NixOS/nixpkgs/blob/9e7e65f7c5ec6a9cfb4ca7239c78a3d237c160ac/pkgs/by-name/ed/edk2/package.nix#L51-L98
      patches = [
        # pass targetPrefix as an env var
        (fetchpatch {
          url = "https://src.fedoraproject.org/rpms/edk2/raw/08f2354cd280b4ce5a7888aa85cf520e042955c3/f/0021-Tweak-the-tools_def-to-support-cross-compiling.patch";
          hash = "sha256-E1/fiFNVx0aB1kOej2DJ2DlBIs9tAAcxoedym2Zhjxw=";
        })
        # https://github.com/tianocore/edk2/pull/5658
        (fetchpatch {
          name = "fix-cross-compilation-antlr-dlg.patch";
          url = "https://github.com/tianocore/edk2/commit/a34ff4a8f69a7b8a52b9b299153a8fac702c7df1.patch";
          hash = "sha256-u+niqwjuLV5tNPykW4xhb7PW2XvUmXhx5uvftG1UIbU=";
        })

        ./remove-gcc-prefix-checks.diff
      ];
    };

    edk2-nvidia = applyPatches {
      name = "edk2-nvidia";
      src = fetchedRepos.edk2-nvidia;
      patches = edk2NvidiaPatches ++ [
        ./stuart-passthru-compiler-prefix.diff
        ./repeatability.diff
      ] ++ lib.optionals (trustedPublicCertPemFile != null) [
        ./capsule-authentication.diff
      ];
      postPatch = lib.optionalString errorLevelInfo ''
        sed -i 's#PcdDebugPrintErrorLevel|.*#PcdDebugPrintErrorLevel|0x8000004F#' Platform/NVIDIA/NVIDIA.common.dsc.inc
      '' + lib.optionalString (bootLogo != null) ''
        cp ${bootLogoVariants}/logo1080.bmp Silicon/NVIDIA/Drivers/Logo/nvidiagray1080.bmp
        cp ${bootLogoVariants}/logo720.bmp Silicon/NVIDIA/Drivers/Logo/nvidiagray720.bmp
        cp ${bootLogoVariants}/logo480.bmp Silicon/NVIDIA/Drivers/Logo/nvidiagray480.bmp
      '';
    };
  };
  pythonEnv = buildPackages.python312.withPackages (ps: callPackage ./pyenv.nix { inherit ps; inherit (patchedRepos) edk2-nvidia; });

  buildTarget = if debugMode then "DEBUG" else "RELEASE";

  targetArch =
    if stdenv.hostPlatform.isi686 then
      "IA32"
    else if stdenv.hostPlatform.isx86_64 then
      "X64"
    else if stdenv.hostPlatform.isAarch32 then
      "ARM"
    else if stdenv.hostPlatform.isAarch64 then
      "AARCH64"
    else if stdenv.hostPlatform.isRiscV64 then
      "RISCV64"
    else if stdenv.hostPlatform.isLoongArch64 then
      "LOONGARCH64"
    else
      throw "Unsupported architecture";

  mkStuartDrv = platformBuild: extraArgs:
    # TODO: edk2.mkDerivation doesn't have a way to override the edk version used!
    # Make it not via passthru ?
    stdenv.mkDerivation (finalAttrs: {
      pname = "${platformBuild}-edk2-uefi-${buildTarget}";
      version = l4tMajorMinorPatchVersion;

      srcs = builtins.attrValues patchedRepos;

      sourceRoot = ".";

      depsBuildBuild = [ buildPackages.stdenv.cc buildPackages.bash libuuid ];
      nativeBuildInputs = [
        pythonEnv

        # from nixpkgs, for stuart
        acpica-tools
        dtc
        nasm
        unixtools.whereis
        which
      ];
      strictDeps = true;

      # trick taken from https://src.fedoraproject.org/rpms/edk2/blob/08f2354cd280b4ce5a7888aa85cf520e042955c3/f/edk2.spec#_319
      ${"GCC_${targetArch}_PREFIX"} = stdenv.cc.targetPrefix;
      # stuart (nvidia extensions) really wants CROSS_COMPILER_PREFIX to look like this
      CROSS_COMPILER_PREFIX = "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}";
      # Version is ${FIRMWARE_VERSION_BASE}-${GIT_SYNC_REVISION}
      FIRMWARE_VERSION_BASE = "${l4tMajorMinorPatchVersion}";

      # see nixpkgs/pkgs/by-name/ed/edk2/package.nix
      hardeningDisable = [
        "format"
        "fortify"
      ];

      patches = edk2UefiPatches;

      patchPhase = ''
        find . -name \*_ext_dep.yaml -delete
        patchShebangs .
      '';

      configurePhase = ''
        runHook preConfigure

        unset AR
        unset AS
        unset CC
        unset CXX
        unset LD
        unset NM
        unset OBJCOPY
        unset OBJDUMP
        unset RANLIB
        unset READELF
        unset SIZE
        unset STRINGS
        unset STRIP

        export WORKSPACE=$(pwd)
        export GIT_SYNC_REVISION=$(printf "%s-%s" "${uniqueHash}" "$out" | sha256sum | head -c 12)
        CFLAGS=$NIX_CFLAGS_COMPILE_FOR_BUILD LDFLAGS=$NIX_LDFLAGS_FOR_BUILD python edk2/BaseTools/Edk2ToolsBuild.py -t GCC5
        # DANGER: If someone else modifies PYTHONPATH, then we lose this
        # We're okay when this was written.
        export PYTHONPATH=$(pwd)/edk2-nvidia/Silicon/NVIDIA

        ${lib.optionalString (trustedPublicCertPemFile != null) ''
        echo Using ${trustedPublicCertPemFile} as public certificate for capsule verification
        ${lib.getExe buildPackages.openssl} x509 -outform DER -in ${trustedPublicCertPemFile} -out edk2/PublicCapsuleKey.cer
        python3 edk2/BaseTools/Scripts/BinToPcd.py -p gEfiSecurityPkgTokenSpaceGuid.PcdPkcs7CertBuffer -i edk2/PublicCapsuleKey.cer -o edk2/PublicCapsuleKey.cer.gEfiSecurityPkgTokenSpaceGuid.PcdPkcs7CertBuffer.inc
        python3 edk2/BaseTools/Scripts/BinToPcd.py -x -p gFmpDevicePkgTokenSpaceGuid.PcdFmpDevicePkcs7CertBufferXdr -i edk2/PublicCapsuleKey.cer -o edk2/PublicCapsuleKey.cer.gFmpDevicePkgTokenSpaceGuid.PcdFmpDevicePkcs7CertBufferXdr.inc
        ''}

        runHook postConfigure
      '';

      buildPhase = ''
        stuart_setup -c "edk2-nvidia/Platform/NVIDIA/${platformBuild}/PlatformBuild.py"
        stuart_build -c "edk2-nvidia/Platform/NVIDIA/${platformBuild}/PlatformBuild.py" ${extraArgs} --target ${buildTarget}
      '';

      installPhase = ''
        runHook preInstall
        mv -v Build/*/* $out
        mv -v reports/* $out
        runHook postInstall
      '';
    });

  jetsonUefi = mkStuartDrv "Tegra" "--init-defconfig edk2-nvidia/Platform/NVIDIA/Tegra/DefConfigs/${defconfig}.defconfig";
  jetsonStandaloneMMOptee = mkStuartDrv "StandaloneMmOptee" "";

  uefi-firmware = runCommand "uefi-firmware-${l4tMajorMinorPatchVersion}"
    {
      nativeBuildInputs = [ python3 nukeReferences ];
      passthru = {
        # Keep in sync with FIRMWARE_VERSION_BASE and GIT_SYNC_REVISION above
        biosVersion = "${l4tMajorMinorPatchVersion}-" + lib.substring 0 12 (builtins.hashString "sha256" "${uniqueHash}-${jetsonUefi}");
        inherit jetsonUefi jetsonStandaloneMMOptee;
      } // patchedRepos;
    }
    (''
      mkdir -p $out
      python3 ${patchedRepos.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetsonUefi}/FV/UEFI_NS.Fv \
        $out/uefi_jetson.bin

      python3 ${patchedRepos.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetsonUefi}/AARCH64/L4TLauncher.efi \
        $out/L4TLauncher.efi

      # Get rid of any string references to source(s)
      nuke-refs $out/uefi_jetson.bin
    '' + lib.optionalString (socFamily == "t19x" || socFamily == "t23x") ''
      python3 ${patchedRepos.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetsonStandaloneMMOptee}/FV/UEFI_MM.Fv \
        $out/standalonemm_optee.bin

      nuke-refs $out/standalonemm_optee.bin
    '');
in
{
  inherit uefi-firmware;
}


