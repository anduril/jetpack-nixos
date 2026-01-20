{ lib
, callPackage
, buildPackages
, fetchFromGitHub
, fetchpatch
, runCommand
, python3
, applyPatches
, nukeReferences
, l4tMajorMinorPatchVersion
, uniqueHash ? ""
  # The root certificate (in PEM format) for authenticating capsule updates. By
  # default, EDK2 authenticates using a test keypair commited upstream.
, trustedPublicCertPemFile ? null
, ...
}@args:

let
  # See: https://github.com/NVIDIA/edk2-edkrepo-manifest/blob/main/edk2-nvidia/Platform/NVIDIAPlatformsManifest.xml
  defaultOrigin = {
    owner = "NVIDIA";
    rev = "r${l4tMajorMinorPatchVersion}";
  };
  repos = {
    edk2 = {
      sha256 = "sha256-TBroMmFyZt6ypooDtSzScjA3POPr76rJKfLQfAkRwdU=";
      fetchSubmodules = true;
    };
    edk2-platforms.sha256 = "sha256-27dKEi66UWBgJi3Sb2/naeeSC2CJ5+Dbtw8e0o5Y/Hg=";
    edk2-non-osi.sha256 = "sha256-FnznH8KsB3rD7sL5Lx2GuQZRPZ+uqAYqenjk+7x89mE=";
    edk2-nvidia.sha256 = "sha256-eTX+/B6TtpYyeoeQxJcoN2eS+Mh4DtLthabW7p7jzYQ=";
    edk2-nvidia-non-osi.sha256 = "sha256-5BjT7kZqU8ek9GC7f1KuomC2JYyWWFMawrZN2CPHGjY=";
  };

  fetchRepo = name: value: fetchFromGitHub (defaultOrigin // { inherit name; repo = name; } // value);
  fetchedRepos = builtins.mapAttrs fetchRepo repos;

  patchedRepos = fetchedRepos // {
    edk2 = applyPatches {
      name = "edk2";
      src = fetchedRepos.edk2.overrideAttrs
        # see https://github.com/NixOS/nixpkgs/pull/354193
        {
          env = {
            GIT_CONFIG_COUNT = 1;
            GIT_CONFIG_KEY_0 = "url.https://github.com/tianocore/edk2-subhook.git.insteadOf";
            GIT_CONFIG_VALUE_0 = "https://github.com/Zeex/subhook.git";
          };
        };
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

        # MdePkg/BaseFdtLib: fix build with gcc 15
        (fetchpatch {
          url = "https://github.com/tianocore/edk2/commit/c0796335d3c6362b563844410499ff241d42ac63.patch";
          sha256 = "sha256-F6wTh8xl+79AZmhhTTmeg7Cu7O2tFlh2JGQ5sYEfZ/o=";
        })

        # BaseTools/Pccts: set C standard
        (fetchpatch {
          url = "https://github.com/tianocore/edk2/commit/e063f8b8a53861043b9872cc35b08a3dc03b0942.patch";
          sha256 = "sha256-KYkH0gBjdu12CDdwxMw0Un1Y7nwShuuhxoah9JDX/eg=";
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

    edk2-nvidia = applyPatches {
      name = "edk2-nvidia";
      src = fetchedRepos.edk2-nvidia;

      patches = [
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

        # feat: Add Aquantia AQR113 PHY ID
        (fetchpatch {
          url = "https://github.com/NVIDIA/edk2-nvidia/commit/772fecc942cd9e75260875d8cffa74367b7349ef.patch";
          sha256 = "sha256-LxwLx6SW9XUJOm/DpdyfenWG/4Oec6/Dgu/ZLviFNvk=";
        })

        ./stuart-passthru-compiler-prefix.diff
        ./repeatability.diff
        ./add-extra-oui-for-mgbe-phy.diff

        # fix: XusbControllerDxe Fix build with gcc-15
        (fetchpatch {
          url = "https://github.com/NVIDIA/edk2-nvidia/commit/91330517f239bae03a5220265987a525724aa7bc.patch";
          sha256 = "sha256-nQCXU2CJYtGzBvCGUsdRpw+jomvl4DWKGLdQOjJWdZ4=";
        })
      ] ++ lib.optionals (trustedPublicCertPemFile != null) [
        ./capsule-authentication.diff
      ];
    };
  };

  mkStuartDrv = callPackage ../stuart.nix (args // { srcs = patchedRepos; });

  jetsonUefi = mkStuartDrv {
    platformBuild = "Jetson";
    outputs = [
      "FV/UEFI_NS.Fv"
      "AARCH64/L4TLauncher.efi"
      "AARCH64/Silicon/NVIDIA/Tegra/DeviceTree/DeviceTree/OUTPUT/*.dtb"
    ];
  };

  jetsonUefiMinimal = mkStuartDrv {
    platformBuild = "JetsonMinimal";
    outputs = [ "FV/UEFI_NS.Fv" ];
  };

  jetsonStandaloneMMOptee = mkStuartDrv {
    platformBuild = "StandaloneMmOptee";
    outputs = [ "FV/UEFI_MM.Fv" ];
  };

  uefi-firmware = runCommand "uefi-firmware-${l4tMajorMinorPatchVersion}"
    {
      nativeBuildInputs = [ python3 nukeReferences ];
      # Keep in sync with FIRMWARE_VERSION_BASE and GIT_SYNC_REVISION above
      passthru = {
        biosVersion = "${l4tMajorMinorPatchVersion}-" + lib.substring 0 12 (builtins.hashString "sha256" "${uniqueHash}-${jetsonUefi}");
        inherit jetsonUefi jetsonUefiMinimal jetsonStandaloneMMOptee;
      } // patchedRepos;
    }
    ''
      mkdir -p $out
      python3 ${patchedRepos.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetsonUefi}/UEFI_NS.Fv \
        $out/uefi_jetson.bin

      python3 ${patchedRepos.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetsonUefi}/L4TLauncher.efi \
        $out/L4TLauncher.efi

      mkdir -p $out/dtbs
      for filename in ${jetsonUefi}/*.dtb; do
        cp $filename $out/dtbs/$(basename "$filename" ".dtb").dtbo
      done

      python3 ${patchedRepos.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetsonUefiMinimal}/UEFI_NS.Fv \
        $out/uefi_jetson_minimal.bin

      python3 ${patchedRepos.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetsonStandaloneMMOptee}/UEFI_MM.Fv \
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


