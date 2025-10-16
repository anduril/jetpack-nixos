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

  # See: https://github.com/NVIDIA/edk2-edkrepo-manifest/blob/main/edk2-nvidia/Platform/NVIDIAPlatformsManifest.xml
  edk2-src = applyPatches {
    name = "edk2";
    src = (fetchFromGitHub {
      owner = "NVIDIA";
      repo = "edk2";
      rev = "r${l4tMajorMinorPatchVersion}";
      fetchSubmodules = true;
      hash = "sha256-TBroMmFyZt6ypooDtSzScjA3POPr76rJKfLQfAkRwdU=";
    }).overrideAttrs
      # see https://github.com/NixOS/nixpkgs/pull/354193
      {
        env = {
          GIT_CONFIG_COUNT = 1;
          GIT_CONFIG_KEY_0 = "url.https://github.com/tianocore/edk2-subhook.git.insteadOf";
          GIT_CONFIG_VALUE_0 = "https://github.com/Zeex/subhook.git";
        };
      };
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
      (fetchpatch {
        name = "[PATCH] MdePkg: Check if compiler has __has_builtin before trying to";
        url = "https://github.com/tianocore/edk2/commit/57a890fd03356350a1b7a2a0064c8118f44e9958.patch";
        hash = "sha256-on+yJOlH9B2cD1CS9b8Pmg99pzrlrZT6/n4qPHAbDcA=";
      })

      ./remove-gcc-prefix-checks.diff
    ];

    # EDK2 is currently working on OpenSSL 3.3.x support. Use buildpackages.openssl again,
    # when "https://github.com/tianocore/edk2/pull/6167" is merged.
    postPatch = ''
      # We don't want EDK2 to keep track of OpenSSL, they're frankly bad at it.
      rm -r CryptoPkg/Library/OpensslLib/openssl
      mkdir -p CryptoPkg/Library/OpensslLib/openssl
      (
      cd CryptoPkg/Library/OpensslLib/openssl
      tar --strip-components=1 -xf ${buildPackages.openssl_3.src}

      # Apply OpenSSL patches.
      ${lib.pipe buildPackages.openssl_3.patches [
        (builtins.filter (
          patch:
          !builtins.elem (baseNameOf patch) [
            # Exclude patches not required in this context.
            "nix-ssl-cert-file.patch"
            "openssl-disable-kernel-detection.patch"
            "use-etc-ssl-certs-darwin.patch"
            "use-etc-ssl-certs.patch"
          ]
        ))
        (map (patch: "patch -p1 < ${patch}\n"))
        lib.concatStrings
      ]}
      )

      # enable compilation using Clang
      # https://bugzilla.tianocore.org/show_bug.cgi?id=4620
      substituteInPlace BaseTools/Conf/tools_def.template --replace-fail \
        'DEFINE CLANGPDB_WARNING_OVERRIDES    = ' \
        'DEFINE CLANGPDB_WARNING_OVERRIDES    = -Wno-unneeded-internal-declaration '
    '';
  };

  edk2-platforms = fetchFromGitHub rec {
    owner = "NVIDIA";
    repo = "edk2-platforms";
    name = repo;
    rev = "r${l4tMajorMinorPatchVersion}";
    sha256 = "sha256-27dKEi66UWBgJi3Sb2/naeeSC2CJ5+Dbtw8e0o5Y/Hg=";
  };

  edk2-non-osi = fetchFromGitHub rec {
    owner = "NVIDIA";
    repo = "edk2-non-osi";
    name = repo;
    rev = "r${l4tMajorMinorPatchVersion}";
    sha256 = "sha256-FnznH8KsB3rD7sL5Lx2GuQZRPZ+uqAYqenjk+7x89mE=";
  };

  edk2-nvidia = applyPatches {
    name = "edk2-nvidia";
    src = fetchFromGitHub {
      owner = "NVIDIA";
      repo = "edk2-nvidia";
      rev = "r${l4tMajorMinorPatchVersion}";
      sha256 = "sha256-eTX+/B6TtpYyeoeQxJcoN2eS+Mh4DtLthabW7p7jzYQ=";
    };
    patches = edk2NvidiaPatches ++ [
      ###### git log r36.4.3-updates ^r36.4.3 (kept these even in 36.4.4) ######
      (fetchpatch {
        # fix: Leave DisplayHandoff enabled on ACPI boot
        url = "https://github.com/NVIDIA/edk2-nvidia/commit/7b2c3a5b0b1639a71df6770152d547f2d27740a5.patch";
        hash = "sha256-ONVHv0KhO4Xwr7dJUxNfsZJNesxBzCQAnI7/sWZHrCA=";
      })
      (fetchpatch {
        # fix: Early free of device nodes in AcpiDtbSsdtGenerator
        url = "https://github.com/NVIDIA/edk2-nvidia/commit/cecfa36d3b600e932880d7d97d17c8080d87d97b.patch";
        hash = "sha256-lT6tunO3mmAzv4MtFmH+gpkWvvhH9ejgxMumS3s4qSY=";
      })
      (fetchpatch {
        # fix: bug in block erase logic
        url = "https://github.com/NVIDIA/edk2-nvidia/commit/fc333bd6dcb7e0921303f35ee01055ef33df444b.patch";
        hash = "sha256-1IxQYgmpcGdF7ckhmmxa2Y+P59qXYTRvV7lrb2xbQl0=";
      })
      (fetchpatch {
        # fix: bug in secureboot hash compute and optimize reads
        url = "https://github.com/NVIDIA/edk2-nvidia/commit/9d4a790e7786d9699405f15927f2fc391915bb19.patch";
        hash = "sha256-MVzWEzzKPRfDWiqgGnfl9dwgDnPLJxjsvijH5jM2Pgw=";
      })
      #####################################################

      # Fix Eqos driver to use correct TX clock name
      # PR: https://github.com/NVIDIA/edk2-nvidia/pull/76
      (fetchpatch {
        url = "https://github.com/NVIDIA/edk2-nvidia/commit/26f50dc3f0f041d20352d1656851c77f43c7238e.patch";
        hash = "sha256-cc+eGLFHZ6JQQix1VWe/UOkGunAzPb8jM9SXa9ScIn8=";
      })

      ./stuart-passthru-compiler-prefix.diff
      ./repeatability.diff
      ./add-extra-oui-for-mgbe-phy.diff
    ] ++ lib.optionals (trustedPublicCertPemFile != null) [
      ./capsule-authentication.diff
    ];
    postPatch = lib.optionalString errorLevelInfo ''
      sed -i 's#PcdDebugPrintErrorLevel|.*#PcdDebugPrintErrorLevel|0x8000004F#' Platform/NVIDIA/NVIDIA.common.dsc.inc
    '' + lib.optionalString (bootLogo != null) ''
      cp ${bootLogoVariants}/logo1080.bmp Silicon/NVIDIA/Assets/nvidiagray1080.bmp
      cp ${bootLogoVariants}/logo720.bmp Silicon/NVIDIA/Assets/nvidiagray720.bmp
      cp ${bootLogoVariants}/logo480.bmp Silicon/NVIDIA/Assets/nvidiagray480.bmp
    '';
  };

  edk2-nvidia-non-osi = fetchFromGitHub rec {
    owner = "NVIDIA";
    repo = "edk2-nvidia-non-osi";
    name = repo;
    rev = "r${l4tMajorMinorPatchVersion}";
    sha256 = "sha256-5BjT7kZqU8ek9GC7f1KuomC2JYyWWFMawrZN2CPHGjY=";
  };

  pythonEnv = buildPackages.python312.withPackages (ps: callPackage ./pyenv.nix { inherit ps edk2-nvidia; });

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

  mkStuartDrv = platformBuild:
    # TODO: edk2.mkDerivation doesn't have a way to override the edk version used!
    # Make it not via passthru ?
    stdenv.mkDerivation (finalAttrs: {
      pname = "${platformBuild}-edk2-uefi-${buildTarget}";
      version = l4tMajorMinorPatchVersion;

      srcs = [
        edk2-src
        edk2-platforms
        edk2-non-osi
        edk2-nvidia
        edk2-nvidia-non-osi
      ];

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
      ${"GCC5_${targetArch}_PREFIX"} = stdenv.cc.targetPrefix;
      # stuart (nvidia extensions) really wants CROSS_COMPILER_PREFIX to look like this
      CROSS_COMPILER_PREFIX = "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}";
      # DANGER: If someone else modifies PYTHONPATH, then we lose this
      # We're okay when this was written.
      PYTHONPATH = "${edk2-nvidia}/Silicon/NVIDIA";
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
        stuart_build -c "edk2-nvidia/Platform/NVIDIA/${platformBuild}/PlatformBuild.py" --target ${buildTarget}
      '';

      installPhase = ''
        runHook preInstall
        mv -v Build/*/* $out
        mv -v reports/* $out
        runHook postInstall
      '';
    });

  jetson-edk2-uefi = mkStuartDrv "Jetson";
  jetson-edk2-uefi-minimal = mkStuartDrv "JetsonMinimal";
  jetson-edk-uefi-stmm-optee = mkStuartDrv "StandaloneMmOptee";

  uefi-firmware = runCommand "uefi-firmware-${l4tMajorMinorPatchVersion}"
    {
      nativeBuildInputs = [ python3 nukeReferences ];
      # Keep in sync with FIRMWARE_VERSION_BASE and GIT_SYNC_REVISION above
      passthru.biosVersion = "${l4tMajorMinorPatchVersion}-" + lib.substring 0 12 (builtins.hashString "sha256" "${uniqueHash}-${jetson-edk2-uefi}");
    }
    ''
      mkdir -p $out
      python3 ${edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetson-edk2-uefi}/FV/UEFI_NS.Fv \
        $out/uefi_jetson.bin

      python3 ${edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetson-edk2-uefi}/AARCH64/L4TLauncher.efi \
        $out/L4TLauncher.efi

      mkdir -p $out/dtbs
      for filename in ${jetson-edk2-uefi}/AARCH64/Silicon/NVIDIA/Tegra/DeviceTree/DeviceTree/OUTPUT/*.dtb; do
        cp $filename $out/dtbs/$(basename "$filename" ".dtb").dtbo
      done

      python3 ${edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetson-edk2-uefi-minimal}/FV/UEFI_NS.Fv \
        $out/uefi_jetson_minimal.bin

      python3 ${edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetson-edk-uefi-stmm-optee}/FV/UEFI_MM.Fv \
        $out/standalonemm_optee.bin

      # Get rid of any string references to source(s)
      nuke-refs $out/uefi_jetson.bin
      nuke-refs $out/uefi_jetson_minimal.bin
      nuke-refs $out/standalonemm_optee.bin
    '';
in
{
  inherit uefi-firmware;
}


