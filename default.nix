{ callPackage, callPackages, stdenv, stdenvNoCC, lib, runCommand, fetchurl,
  autoPatchelfHook, bzip2_1_1, writeShellScriptBin, pkgs, dtc,
}:

let
  # Grab this from nixpkgs cudaPackages
  inherit (pkgs.cudaPackages) autoAddOpenGLRunpathHook;

  pkgsAarch64 = if pkgs.stdenv.buildPlatform.isAarch64 then pkgs else pkgs.pkgsCross.aarch64-multiplatform;

  # https://developer.nvidia.com/embedded/jetson-linux-archive
  # https://repo.download.nvidia.com/jetson/

  src = fetchurl {
    url = "https://developer.nvidia.com/embedded/l4t/r35_release_v1.0/release/jetson_linux_r35.1.0_aarch64.tbz2";
    sha256 = "sha256-ZwAh9qKIuOqRb9QIn73emrjdUAPyMHmq9DlCSzXeRUw=";
  };

  debs = import ./debs { inherit lib fetchurl; };

  jetpackVersion = "5.0.2";
  l4tVersion = "35.1.0";
  cudaVersion = "11.4";

  # we use a more recent version of bzip2 here because we hit this bug extracting nvidia's archives:
  # https://bugs.launchpad.net/ubuntu/+source/bzip2/+bug/1834494
  bspSrc = runCommand "l4t-unpacked" { nativeBuildInputs = [ bzip2_1_1 ]; } ''
    bzip2 -d -c ${src} | tar xf -
    mv Linux_for_Tegra $out
  '';

  # Just for convenience. Unused
  unpackedDebs = pkgs.runCommand "unpackedDebs" { nativeBuildInputs = [ pkgs.dpkg ]; } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") debs.common)}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") debs.t234)}
  '';

  # Fixed version of edk that works with cross-compilation
  # TODO: Remove when we upgrade beyond 22.05
  edk2 = callPackage ./edk2.nix {};

  jetson-firmware = (pkgsAarch64.callPackages ./jetson-firmware.nix {
    inherit edk2;
  }).jetson-firmware;

  flash-tools = callPackage ./flash-tools.nix {
    inherit bspSrc l4tVersion;
  };

  l4t = callPackages ./l4t.nix { inherit debs l4tVersion; };

  cudaPackages = callPackages ./cuda-packages.nix { inherit debs cudaVersion autoAddOpenGLRunpathHook l4t; };

  samples = callPackages ./samples.nix { inherit debs cudaVersion autoAddOpenGLRunpathHook l4t cudaPackages; };

  kernel = callPackage ./kernel { inherit (l4t) l4t-xusb-firmware; };
  kernelPackagesOverlay = self: super: {
    nvidia-display-driver = self.callPackage ./kernel/display-driver.nix {};
  };
  kernelPackages = (pkgs.linuxPackagesFor kernel).extend kernelPackagesOverlay;

  rtkernel = callPackage ./kernel { inherit (l4t) l4t-xusb-firmware; realtime = true; };
  rtkernelPackages = (pkgs.linuxPackagesFor rtkernel).extend kernelPackagesOverlay;
in rec {
  inherit jetpackVersion l4tVersion cudaVersion;

  # Just for convenience
  inherit bspSrc debs unpackedDebs;

  inherit cudaPackages samples;
  inherit flash-tools;

  inherit kernel kernelPackages;
  inherit rtkernel rtkernelPackages;

  # TODO: Source packages. source_sync.sh from bspSrc
  # OPTEE
  #   nv-tegra.nvidia.com/tegra/optee-src/atf.git
  #   nv-tegra.nvidia.com/tegra/optee-src/nv-optee.git
  # GST plugins

  # Generate a flash script using the built configuration options set in a NixOS configuration
  flashScriptFromNixos = config: let
    cfg = config.hardware.nvidia-jetpack;
  in callPackage ./flash-script.nix {
    name = config.networking.hostName;
    inherit (cfg.flashScriptOverrides)
      flashArgs partitionTemplate;

    flash-tools = flash-tools.overrideAttrs ({ postPatch ? "", ... }: {
      postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
    });

    jetson-firmware = jetson-firmware.override {
      bootLogo = cfg.bootloader.logo;
      debugMode = cfg.bootloader.debugMode;
      errorLevelInfo = cfg.bootloader.errorLevelInfo;
      edk2NvidiaPatches = cfg.bootloader.edk2NvidiaPatches;
    };

    dtbsDir = config.hardware.deviceTree.package;
  };

  flash-scripts = rec {
    # Generic flash script which contains the default NVIDIA devices without any patches
    flash-generic = callPackage ./flash-script.nix {
      inherit flash-tools jetson-firmware;
      # Use cross-compiled machine here so we don't have to depend on aarch64 builders
      # TODO: Do a smaller cross-compiled version from old jetpack dir
      dtbsDir = (pkgsAarch64.nixos {
        imports = [ ./modules/default.nix ];
        hardware.nvidia-jetpack.enable = true;
      }).config.hardware.deviceTree.package;
    };
  } // (lib.mapAttrs' (n: c: lib.nameValuePair "flash-${n}" (flashScriptFromNixos (pkgs.nixos {
    imports = [ ./modules/default.nix { hardware.nvidia-jetpack = c; } ];
    hardware.nvidia-jetpack.enable = true;
    networking.hostName = n; # Just so it sets the flash binary name.
  }).config)) {
    "orin-agx-devkit" = { som = "orin-agx"; carrierBoard = "devkit"; bootloader.edk2NvidiaPatches = [ ./edk2-uefi-dtb.patch ]; };
    "xavier-agx-devkit" = { som = "xavier-agx"; carrierBoard = "devkit"; };
    "xavier-nx-devkit" = { som = "xavier-nx"; carrierBoard = "devkit"; };
    "xavier-nx-devkit-emmc" = { som = "xavier-nx-emmc"; carrierBoard = "devkit"; };
  });
}
// l4t
// callPackage ./jetson-firmware.nix { inherit edk2; }
