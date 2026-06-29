{ lib
, buildPackages
, callPackage
, fetchFromGitHub
, fetchpatch
, runCommand
, python3
, applyPatches
, nukeReferences
, l4tMajorMinorPatchVersion
, patchfv
, uniqueHash ? ""
, socFamily ? "t26x"
, defconfig ? "${socFamily}_general"
  # The root certificate (in PEM format) for authenticating capsule updates. By
  # default, EDK2 authenticates using a test keypair commited upstream.
, trustedPublicCertPemFile ? null
, ...
}@args:

let
  tagVersion = if lib.versions.patch l4tMajorMinorPatchVersion == "0" then lib.versions.majorMinor l4tMajorMinorPatchVersion else l4tMajorMinorPatchVersion;

  # See: https://github.com/NVIDIA/edk2-edkrepo-manifest/blob/7b298576d93b0fae216aee7a1539268f4ce9c6a9/edk2-nvidia/Platform/NVIDIAPlatformsManifest.xml#L306
  defaultOrigin = {
    owner = "NVIDIA";
    rev = "r${tagVersion}";
  };
  repos = {
    edk2 = {
      sha256 = "sha256-3y56DRZwFri5K8S2wpYoACEyHlNJ3KMXAkme8UnIaU0=";
      fetchSubmodules = true;
    };
    edk2-non-osi.sha256 = "sha256-6yuvVvmGn4yaEksbbvGDX1ZcKpdWBKnwaNjLGvgAWyk=";
    edk2-platforms.sha256 = "sha256-7SGml17A47+wZNn4Z9vZHjDYTAcxIyG6De9vU4U8QR8=";
    edk2-infineon.sha256 = "sha256-47UJfEd4ViTenx5dvy2G75NFSgmcsyIWpN0Lv1QlvA8=";
    edk2-redfish-client.sha256 = "sha256-Tq6dZu90T10FBVMYjYolm2WfAZc/cQe8dNuKXrK3RbE=";
    edk2-nvidia.sha256 = "sha256-fR7RB1kRnPX1yf6HWliLQhNPBmg8CGaumzPPaUPDQak=";
    edk2-nvidia-non-osi.sha256 = "sha256-xdIcdgmvFZgF2R8sjDVIrW8w2XLeDhI8kGpoW8gdNgE=";
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

        # UEFI firmware fail fails to boot unless we have a fTPM in OP-TEE. Disabling for now until we build/ship the fTPM TA.
        ./disable-ftpm.diff
      ] ++ lib.optionals (trustedPublicCertPemFile != null) [
        ./capsule-authentication.diff
      ];
    };
  };

  fakeHash = "123456789012";
  fakeVersion = "${l4tMajorMinorPatchVersion}-${fakeHash}";
  biosVersion = "${l4tMajorMinorPatchVersion}-" + lib.substring 0 12 (builtins.hashString "sha256" "${uniqueHash}-${unstamped-firmware}");

  mkStuartDrv = callPackage ../stuart.nix (args // { srcs = patchedRepos; uniqueHash = fakeHash; });

  unstamped-firmware = mkStuartDrv {
    platformBuild = "Tegra";
    stuartExtraArgs = "--init-defconfig edk2-nvidia/Platform/NVIDIA/Tegra/DefConfigs/${defconfig}.defconfig";
    outputs = [
      "FV/UEFI_NS.Fv"
      "AARCH64/L4TLauncher.efi"
      "AARCH64/Silicon/NVIDIA/Tegra/DeviceTree/DeviceTree/OUTPUT/*.dtb"
    ];

    postInstall = ''
      python3 edk2-nvidia/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        $out/UEFI_NS.Fv \
        $out/uefi_jetson.bin
    '';
  };

  uefi-firmware = runCommand "${unstamped-firmware.pname}-${unstamped-firmware.version}-stamped"
    {
      nativeBuildInputs = [ python3 buildPackages.nvidia-jetpack.patchfv ];
      passthru = { inherit biosVersion; };
    } ''
    mkdir -p $out
    cp -r ${unstamped-firmware}/* $out

    rm $out/UEFI_NS.Fv $out/uefi_jetson.bin
    patchfv ${unstamped-firmware}/UEFI_NS.Fv $out/UEFI_NS.Fv ${fakeVersion} ${biosVersion}

    python3 ${patchedRepos.edk2-nvidia}/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        $out/UEFI_NS.Fv \
        $out/uefi_jetson.bin
  '';

  jetsonStandaloneMMOptee = mkStuartDrv {
    platformBuild = "StandaloneMmOptee";
    outputs = [ "FV/UEFI_MM.Fv" ];

    postInstall = ''
      python3 edk2-nvidia/Silicon/NVIDIA/edk2nv/FormatUefiBinary.py \
        $out/UEFI_MM.Fv \
        $out/standalonemm_optee.bin
    '';
  };
in
{
  inherit uefi-firmware jetsonStandaloneMMOptee;
}


