{ callPackage, callPackages, stdenv, stdenvNoCC, lib, runCommand, fetchurl,
  bzip2_1_1, dpkg,  pkgs, dtc, python3, runtimeShell, writeShellApplication
}:

let
  # Grab this from nixpkgs cudaPackages
  inherit (pkgs.cudaPackages) autoAddOpenGLRunpathHook;

  pkgsAarch64 = if pkgs.stdenv.buildPlatform.isAarch64 then pkgs else pkgs.pkgsCross.aarch64-multiplatform;

  jetpackVersion = "5.1.2";
  l4tVersion = "35.4.1";
  cudaVersion = "11.4";

  # https://developer.nvidia.com/embedded/jetson-linux-archive
  # https://repo.download.nvidia.com/jetson/

  src = fetchurl {
    url = with lib.versions; "https://developer.download.nvidia.com/embedded/L4T/r${major l4tVersion}_Release_v${minor l4tVersion}.${patch l4tVersion}/release/Jetson_Linux_R${l4tVersion}_aarch64.tbz2";
    sha256 = "sha256-crdaDH+jv270GuBmNLtnw4qSaCFV0SBgJtvuSmuaAW8=";
  };

  debs = import ./debs { inherit lib fetchurl l4tVersion; };

  # we use a more recent version of bzip2 here because we hit this bug extracting nvidia's archives:
  # https://bugs.launchpad.net/ubuntu/+source/bzip2/+bug/1834494
  bspSrc = runCommand "l4t-unpacked" { nativeBuildInputs = [ bzip2_1_1 ]; } ''
    bzip2 -d -c ${src} | tar xf -
    mv Linux_for_Tegra $out
  '';

  # Just for convenience. Unused
  unpackedDebs = pkgs.runCommand "unpackedDebs" { nativeBuildInputs = [ dpkg ]; } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") debs.common)}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") debs.t234)}
  '';

  inherit (pkgsAarch64.callPackages ./uefi-firmware.nix { inherit l4tVersion; })
    edk2-jetson uefi-firmware;

  inherit (pkgsAarch64.callPackages ./optee.nix {
    # Nvidia's recommended toolchain is gcc9:
    # https://nv-tegra.nvidia.com/r/gitweb?p=tegra/optee-src/nv-optee.git;a=blob;f=optee/atf_and_optee_README.txt;h=591edda3d4ec96997e054ebd21fc8326983d3464;hb=5ac2ab218ba9116f1df4a0bb5092b1f6d810e8f7#l33
    stdenv = pkgsAarch64.gcc9Stdenv;
    inherit bspSrc l4tVersion;
  }) buildTOS opteeClient;

  flash-tools = callPackage ./flash-tools.nix {
    inherit bspSrc l4tVersion;
  };

  board-automation = callPackage ./board-automation.nix {
    inherit bspSrc l4tVersion;
  };

  python-jetson = python3.pkgs.callPackage ./python-jetson.nix { };

  tegra-eeprom-tool = pkgsAarch64.callPackage ./tegra-eeprom-tool.nix { };
  tegra-eeprom-tool-static = pkgsAarch64.pkgsStatic.callPackage ./tegra-eeprom-tool.nix { };

  l4t = callPackages ./l4t.nix { inherit debs l4tVersion; };

  cudaPackages = callPackages ./cuda-packages.nix { inherit debs cudaVersion autoAddOpenGLRunpathHook l4t; };

  samples = callPackages ./samples.nix { inherit debs cudaVersion autoAddOpenGLRunpathHook l4t cudaPackages; };

  kernel = callPackage ./kernel { inherit (l4t) l4t-xusb-firmware; kernelPatches = []; };
  kernelPackagesOverlay = self: super: {
    nvidia-display-driver = self.callPackage ./kernel/display-driver.nix { inherit l4tVersion; };
  };
  kernelPackages = (pkgs.linuxPackagesFor kernel).extend kernelPackagesOverlay;

  rtkernel = callPackage ./kernel { inherit (l4t) l4t-xusb-firmware; kernelPatches = [];  realtime = true; };
  rtkernelPackages = (pkgs.linuxPackagesFor rtkernel).extend kernelPackagesOverlay;

  nxJetsonBenchmarks = pkgs.callPackage ./jetson-benchmarks/default.nix {
    targetSom = "nx";
    inherit cudaPackages;
  };
  xavierAgxJetsonBenchmarks = pkgs.callPackage ./jetson-benchmarks/default.nix {
    targetSom = "xavier-agx";
    inherit cudaPackages;
  };
  orinAgxJetsonBenchmarks = pkgs.callPackage ./jetson-benchmarks/default.nix {
    targetSom = "orin-agx";
    inherit cudaPackages;
  };

  supportedConfigurations = lib.listToAttrs (map (c: {
    name = "${c.som}-${c.carrierBoard}";
    value = c;
  }) [
    { som = "orin-agx"; carrierBoard = "devkit"; }
    { som = "orin-agx-industrial"; carrierBoard = "devkit"; }
    { som = "orin-nx"; carrierBoard = "devkit"; }
    { som = "orin-nano"; carrierBoard = "devkit"; }
    { som = "xavier-agx"; carrierBoard = "devkit"; }
    { som = "xavier-nx"; carrierBoard = "devkit"; }
    { som = "xavier-nx-emmc"; carrierBoard = "devkit"; }
  ]);

  supportedNixOSConfigurations = lib.mapAttrs (n: c: {
    imports = [ ./modules/default.nix ];
    hardware.nvidia-jetpack = { enable = true; } // c;
    networking.hostName = "${c.som}-${c.carrierBoard}"; # Just so it sets the flash binary name.
  }) supportedConfigurations;

  flashFromDevice = callPackage ./flash-from-device.nix {
    inherit pkgsAarch64 tegra-eeprom-tool-static;
  };

  # Packages whose contents are paramterized by NixOS configuration
  devicePkgsFromNixosConfig = callPackage ./device-pkgs.nix {
    inherit l4tVersion pkgsAarch64 flash-tools flashFromDevice edk2-jetson uefi-firmware buildTOS bspSrc;
  };

  devicePkgs = lib.mapAttrs (n: c: devicePkgsFromNixosConfig (pkgs.nixos c).config) supportedConfigurations;

  otaUtils = callPackage ./ota-utils {
    inherit tegra-eeprom-tool l4tVersion;
  };
in rec {
  inherit jetpackVersion l4tVersion cudaVersion;

  # Just for convenience
  inherit bspSrc debs unpackedDebs;

  inherit cudaPackages samples;
  inherit flash-tools;
  inherit board-automation; # Allows automation of Orin AGX devkit
  inherit python-jetson; # Allows automation of Xavier AGX devkit
  inherit tegra-eeprom-tool;

  inherit kernel kernelPackages;
  inherit rtkernel rtkernelPackages;

  inherit opteeClient;

  inherit nxJetsonBenchmarks xavierAgxJetsonBenchmarks orinAgxJetsonBenchmarks;

  inherit edk2-jetson uefi-firmware;
  inherit otaUtils;

  # TODO: Source packages. source_sync.sh from bspSrc
  # GST plugins

  inherit flashFromDevice;

  inherit devicePkgsFromNixosConfig;

  devicePkgs = lib.mapAttrs (n: c: devicePkgsFromNixosConfig (pkgs.nixos c).config) supportedNixOSConfigurations;

  flash-generic = writeShellApplication {
    name = "flash-generic";
    text = callPackage ./flash-script.nix {
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

  flashScripts = lib.mapAttrs' (n: c: lib.nameValuePair "flash-${n}" c.flashScript) devicePkgs;
  initrdFlashScripts = lib.mapAttrs' (n: c: lib.nameValuePair "initrd-flash-${n}" c.initrdFlashScript) devicePkgs;
  uefiCapsuleUpdates = lib.mapAttrs' (n: c: lib.nameValuePair "uefi-capsule-update-${n}" c.uefiCapsuleUpdate) devicePkgs;
}
// l4t
