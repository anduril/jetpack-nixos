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
, socFamily ? "t26x"
, defconfig ? "${socFamily}_general"
  # The root certificate (in PEM format) for authenticating capsule updates. By
  # default, EDK2 authenticates using a test keypair commited upstream.
, trustedPublicCertPemFile ? null
, ...
}@args:

let
  # See: https://github.com/NVIDIA/edk2-edkrepo-manifest/blob/7b298576d93b0fae216aee7a1539268f4ce9c6a9/edk2-nvidia/Platform/NVIDIAPlatformsManifest.xml#L306
  defaultOrigin = {
    owner = "NVIDIA";
    rev = "r38.4";
  };
  repos = {
    edk2 = {
      sha256 = "sha256-qfKtBZSRyRlSxEuR4jPFWxMGAiuGteeubrvgwFyLZWY=";
      fetchSubmodules = true;
    };
    edk2-non-osi.sha256 = "sha256-iRsSFFy5UITD1O+ALyocUZkXUQSsIXyq1Ppc/onybU0=";
    edk2-platforms.sha256 = "sha256-PsKxy/tiRl2/qcL/JQNXbUPsnWekAQ+4b+NiccSRGa4=";
    edk2-infineon.sha256 = "sha256-47UJfEd4ViTenx5dvy2G75NFSgmcsyIWpN0Lv1QlvA8=";
    edk2-redfish-client.sha256 = "sha256-EUWi5z+1sz2zMZM6x/sqE2NvdHRkQwQOcotsUwELsBY=";
    edk2-nvidia.sha256 = "sha256-sALmw1KURAe1CdvjW/QcPuOzvPNEwpmk7vNpvii+a70=";
    edk2-nvidia-non-osi.sha256 = "sha256-LIgut03qDx/wRVb2adbo41s+psfI/NIx7GnjOxzGeF4=";
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
      patches = [
        ./stuart-passthru-compiler-prefix.diff
        ./repeatability.diff
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
    ];
  };

  jetsonStandaloneMMOptee = mkStuartDrv {
    platformBuild = "StandaloneMmOptee";
    outputs = [ "FV/UEFI_MM.Fv" ];
  };

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
        ${jetsonUefi}/UEFI_NS.Fv \
        $out/uefi_jetson.bin

      python3 ${patchedRepos.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetsonUefi}/L4TLauncher.efi \
        $out/L4TLauncher.efi

      # Get rid of any string references to source(s)
      nuke-refs $out/uefi_jetson.bin
    '' + lib.optionalString (socFamily == "t19x" || socFamily == "t23x") ''
      python3 ${patchedRepos.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        ${jetsonStandaloneMMOptee}/UEFI_MM.Fv \
        $out/standalonemm_optee.bin

      nuke-refs $out/standalonemm_optee.bin
    '');
in
{
  inherit uefi-firmware;
}


