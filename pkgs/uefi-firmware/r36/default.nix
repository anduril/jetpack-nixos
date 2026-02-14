{ lib
, callPackage
, fetchFromGitHub
, fetchpatch
, runCommand
, python3
, applyPatches
, nukeReferences
, l4tMajorMinorPatchVersion
, uniqueHash ? ""
, socFamily ? "t23x"
, defconfig ? "${socFamily}_general"
  # The root certificate (in PEM format) for authenticating capsule updates. By
  # default, EDK2 authenticates using a test keypair commited upstream.
, trustedPublicCertPemFile ? null
, ...
}@args:

let
  tagVersion = if lib.versions.patch l4tMajorMinorPatchVersion == "0" then lib.versions.majorMinor l4tMajorMinorPatchVersion else l4tMajorMinorPatchVersion;

  # See: https://github.com/NVIDIA/edk2-edkrepo-manifest/blob/main/edk2-nvidia/Platform/NVIDIAPlatformsManifest.xml
  defaultOrigin = {
    owner = "NVIDIA";
    rev = "r${tagVersion}";
  };
  repos = {
    edk2 = {
      sha256 = "sha256-4zFyQ4g+oJp9kkSamx11bfDMRY+9g6Vzsuau9ozC/R0=";
      fetchSubmodules = true;
    };
    edk2-platforms.sha256 = "sha256-PsKxy/tiRl2/qcL/JQNXbUPsnWekAQ+4b+NiccSRGa4=";
    edk2-non-osi.sha256 = "sha256-Dj6Og/sc3MEMU/37rUMu7miHOvFi3Qvfkm+nMSUBUF0=";
    edk2-infineon.sha256 = "sha256-47UJfEd4ViTenx5dvy2G75NFSgmcsyIWpN0Lv1QlvA8=";
    edk2-redfish-client.sha256 = "sha256-EUWi5z+1sz2zMZM6x/sqE2NvdHRkQwQOcotsUwELsBY=";
    edk2-nvidia.sha256 = "sha256-CW1tDcNxA0uod4fmJq3jx1zp+AmS7/akY14zF2LyF4g=";
    edk2-nvidia-non-osi.sha256 = "sha256-bb5pb2nF6Ht5UpTt7Kv2lP46T+MttmgzFCJGd5xnrXs=";
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
    };

    edk2-nvidia = applyPatches {
      name = "edk2-nvidia";
      src = fetchedRepos.edk2-nvidia;

      patches = [
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
    };
  };

  mkStuartDrv = callPackage ../stuart.nix (args // { srcs = patchedRepos; });

  jetsonUefi = mkStuartDrv {
    platformBuild = "Tegra";
    stuartExtraArgs = "--init-defconfig edk2-nvidia/Platform/NVIDIA/Tegra/DefConfigs/${defconfig}.defconfig";
    outputs = [
      "FV/UEFI_NS.Fv"
      "AARCH64/L4TLauncher.efi"
      "AARCH64/Silicon/NVIDIA/Tegra/DeviceTree/DeviceTree/OUTPUT/*.dtb"
    ];
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
        inherit jetsonUefi jetsonStandaloneMMOptee;
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

      python3 ${patchedRepos.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetsonStandaloneMMOptee}/UEFI_MM.Fv \
        $out/standalonemm_optee.bin

      # Get rid of any string references to source(s)
      nuke-refs $out/uefi_jetson.bin
      nuke-refs $out/standalonemm_optee.bin
    '';
in
{
  inherit uefi-firmware;
}


