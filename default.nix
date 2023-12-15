{ callPackage
, callPackages
, stdenv
, stdenvNoCC
, lib
, runCommand
, fetchurl
, bzip2_1_1
, dpkg
, pkgs
, dtc
, python3
, runtimeShell
, writeShellApplication
}:

let
  # Grab this from nixpkgs cudaPackages
  inherit (pkgs.cudaPackages) autoAddOpenGLRunpathHook;

  pkgsAarch64 = if pkgs.stdenv.buildPlatform.isAarch64 then pkgs else pkgs.pkgsCross.aarch64-multiplatform;

  # https://developer.nvidia.com/embedded/jetson-linux-archive
  # https://repo.download.nvidia.com/jetson/

  src = fetchurl {
    url = "https://developer.download.nvidia.com/embedded/L4T/r35_Release_v3.1/release/Jetson_Linux_R35.3.1_aarch64.tbz2";
    sha256 = "sha256-gKVVBKLOnNwKMo7bb9BpBhXE/96cKzL05k4KGjQyouI=";
  };

  debs = import ./debs { inherit lib fetchurl; };

  jetpackVersion = "5.1.1";
  l4tVersion = "35.3.1";
  cudaVersion = "11.4";

  # we use a more recent version of bzip2 here because we hit this bug extracting nvidia's archives:
  # https://bugs.launchpad.net/ubuntu/+source/bzip2/+bug/1834494
  bspSrc = runCommand "l4t-unpacked" { nativeBuildInputs = [ bzip2_1_1 ]; } ''
    bzip2 -d -c ${src} | tar xf -
    mv Linux_for_Tegra $out
  '';

  # Here for convenience, to see what is in upstream Jetpack
  unpackedDebs = pkgs.runCommand "unpackedDebs" { nativeBuildInputs = [ dpkg ]; } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") debs.common)}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") debs.t234)}
  '';

  # Also just for convenience,
  unpackedDebsFilenames = pkgs.runCommand "unpackedDebsFilenames" { nativeBuildInputs = [ dpkg ]; } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Extracting file list from ${n}; dpkg --fsys-tarfile ${p.src} | tar --list > $out/${n}") debs.common)}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Extracting file list from ${n}; dpkg --fsys-tarfile ${p.src} | tar --list > $out/${n}") debs.t234)}
  '';

  inherit (pkgsAarch64.callPackages ./pkgs/uefi-firmware { inherit l4tVersion; })
    edk2-jetson uefi-firmware;

  inherit (pkgsAarch64.callPackages ./pkgs/optee {
    # Nvidia's recommended toolchain is gcc9:
    # https://nv-tegra.nvidia.com/r/gitweb?p=tegra/optee-src/nv-optee.git;a=blob;f=optee/atf_and_optee_README.txt;h=591edda3d4ec96997e054ebd21fc8326983d3464;hb=5ac2ab218ba9116f1df4a0bb5092b1f6d810e8f7#l33
    stdenv = pkgsAarch64.gcc9Stdenv;
    inherit bspSrc l4tVersion;
  }) buildTOS buildOpteeTaDevKit opteeClient;

  flash-tools = callPackage ./pkgs/flash-tools {
    inherit bspSrc l4tVersion;
  };

  board-automation = callPackage ./pkgs/board-automation {
    inherit bspSrc l4tVersion;
  };

  python-jetson = python3.pkgs.callPackage ./pkgs/python-jetson { };

  tegra-eeprom-tool = pkgsAarch64.callPackage ./pkgs/tegra-eeprom-tool { };
  tegra-eeprom-tool-static = pkgsAarch64.pkgsStatic.callPackage ./pkgs/tegra-eeprom-tool { };

  l4t = callPackages ./pkgs/l4t { inherit debs l4tVersion; };

  cudaPackages = callPackages ./pkgs/cuda-packages { inherit debs cudaVersion autoAddOpenGLRunpathHook l4t; };

  samples = callPackages ./pkgs/samples { inherit debs cudaVersion autoAddOpenGLRunpathHook l4t cudaPackages; };

  kernel = callPackage ./kernel { inherit (l4t) l4t-xusb-firmware; kernelPatches = [ ]; };
  kernelPackagesOverlay = self: super: {
    nvidia-display-driver = self.callPackage ./kernel/display-driver.nix { inherit l4tVersion; };
  };
  kernelPackages = (pkgs.linuxPackagesFor kernel).extend kernelPackagesOverlay;

  rtkernel = callPackage ./kernel { inherit (l4t) l4t-xusb-firmware; kernelPatches = [ ]; realtime = true; };
  rtkernelPackages = (pkgs.linuxPackagesFor rtkernel).extend kernelPackagesOverlay;

  nxJetsonBenchmarks = pkgs.callPackage ./pkgs/jetson-benchmarks {
    targetSom = "nx";
    inherit cudaPackages;
  };
  xavierAgxJetsonBenchmarks = pkgs.callPackage ./pkgs/jetson-benchmarks {
    targetSom = "xavier-agx";
    inherit cudaPackages;
  };
  orinAgxJetsonBenchmarks = pkgs.callPackage ./pkgs/jetson-benchmarks {
    targetSom = "orin-agx";
    inherit cudaPackages;
  };

  supportedConfigurations = lib.listToAttrs (map
    (c: {
      name = "${c.som}-${c.carrierBoard}";
      value = c;
    }) [
    { som = "orin-agx"; carrierBoard = "devkit"; }
    { som = "orin-nx"; carrierBoard = "devkit"; }
    { som = "orin-nano"; carrierBoard = "devkit"; }
    { som = "xavier-agx"; carrierBoard = "devkit"; }
    { som = "xavier-nx"; carrierBoard = "devkit"; }
    { som = "xavier-nx-emmc"; carrierBoard = "devkit"; }
  ]);

  supportedNixOSConfigurations = lib.mapAttrs
    (n: c: {
      imports = [ ./modules/default.nix ];
      hardware.nvidia-jetpack = { enable = true; } // c;
      networking.hostName = "${c.som}-${c.carrierBoard}"; # Just so it sets the flash binary name.
    })
    supportedConfigurations;

  flashFromDevice = callPackage ./pkgs/flash-from-device {
    inherit pkgsAarch64 tegra-eeprom-tool-static;
  };

  # Packages whose contents are parameterized by NixOS configuration
  devicePkgsFromNixosConfig = callPackage ./device-pkgs {
    inherit l4tVersion pkgsAarch64 flash-tools flashFromDevice edk2-jetson uefi-firmware buildTOS buildOpteeTaDevKit;
  };

  otaUtils = callPackage ./pkgs/ota-utils {
    inherit tegra-eeprom-tool l4tVersion;
  };
in
rec {
  inherit jetpackVersion l4tVersion cudaVersion;

  # Just for convenience
  inherit bspSrc debs unpackedDebs unpackedDebsFilenames;

  inherit cudaPackages samples;
  inherit flash-tools;
  inherit board-automation; # Allows automation of Orin AGX devkit
  inherit python-jetson; # Allows automation of Xavier AGX devkit
  inherit tegra-eeprom-tool;

  inherit kernel kernelPackages;
  inherit rtkernel rtkernelPackages;

  inherit nxJetsonBenchmarks xavierAgxJetsonBenchmarks orinAgxJetsonBenchmarks;

  inherit edk2-jetson uefi-firmware;
  inherit otaUtils;

  inherit opteeClient;

  # TODO: Source packages. source_sync.sh from bspSrc
  # GST plugins

  inherit flashFromDevice;

  inherit devicePkgsFromNixosConfig;

  devicePkgs = lib.mapAttrs (n: c: devicePkgsFromNixosConfig (pkgs.nixos c).config) supportedNixOSConfigurations;

  flash-generic = writeShellApplication {
    name = "flash-generic";
    text = callPackage ./device-pkgs/flash-script.nix {
      inherit flash-tools uefi-firmware;
      flashCommands = ''
        ${runtimeShell}
      '';
      # Use cross-compiled machine here so we don't have to depend on aarch64 builders
      # TODO: Do a smaller cross-compiled version from old jetpack dir
      dtbsDir = (pkgsAarch64.nixos {
        imports = [ ./modules/default.nix ];
        hardware.nvidia-jetpack.enable = true;
      }).config.hardware.deviceTree.package;
    };
  };

  l4tCsv = callPackage ./pkgs/containers/l4t-csv.nix { inherit bspSrc; };
  genL4tJson = runCommand "l4t.json" { nativeBuildInputs = [ python3 ]; } ''
    python3 ${./pkgs/containers/gen_l4t_json.py} ${l4tCsv} ${unpackedDebsFilenames} > $out
  '';
  containerDeps = callPackage ./pkgs/containers/deps.nix { inherit debs; };
  nvidia-ctk = callPackage ./pkgs/containers/nvidia-ctk.nix { };

  flashScripts = lib.mapAttrs' (n: c: lib.nameValuePair "flash-${n}" c.flashScript) devicePkgs;
  initrdFlashScripts = lib.mapAttrs' (n: c: lib.nameValuePair "initrd-flash-${n}" c.initrdFlashScript) devicePkgs;
  uefiCapsuleUpdates = lib.mapAttrs' (n: c: lib.nameValuePair "uefi-capsule-update-${n}" c.uefiCapsuleUpdate) devicePkgs;
}
  // l4t
