{ callPackage, callPackages, stdenv, stdenvNoCC, lib, runCommand, fetchurl,
  autoPatchelfHook, bzip2_1_1, writeShellScript, runtimeShell, pkgs, dtc,
  imagemagick,
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

  version = "35.1.0";
  cudaVersion = "11.4";

  # we use a more recent version of bzip2 here because we hit this bug extracting nvidia's archives:
  # https://bugs.launchpad.net/ubuntu/+source/bzip2/+bug/1834494
  bspSrc = runCommand "l4t-unpacked" { nativeBuildInputs = [ bzip2_1_1 ]; } ''
    bzip2 -d -c ${src} | tar xf -
    mv Linux_for_Tegra $out
  '';

  # Fixed version of edk that works with cross-compilation
  # TODO: Remove when we upgrade beyond 22.05
  edk2 = callPackage ./edk2.nix {};

  flash-tools = callPackage ./flash-tools.nix {
    inherit bspSrc version;

    # Use cross-compiled machine here so we don't have to depend on aarch64 builders
    # TODO: Do a smaller cross-compiled version from old jetpack dir
    dtbsDir = (pkgsAarch64.nixos (import ./module.nix)).config.hardware.deviceTree.package;

    edk2-firmware = (pkgsAarch64.callPackage ./edk2-firmware.nix {
      inherit edk2;
      # The logo is made available under a CC-BY license. See the repo for details.
      bootLogoVariants = let
        bootLogo = fetchurl {
          url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/e7d4050f2bb39a8c73a31a89e3d55f55536541c3/logo/nixos.svg";
          sha256 = "sha256-E+qpO9SSN44xG5qMEZxBAvO/COPygmn8r50HhgCRDSw=";
        };
      in runCommand "uefi-bootlogo" { nativeBuildInputs = [ imagemagick ]; } ''
        mkdir -p $out
        convert ${bootLogo} -resize 1920x1080 -gravity Center -extent 1920x1080 -format bmp -define bmp:format=bmp3 $out/logo1080.bmp
        convert ${bootLogo} -resize 1280x720  -gravity Center -extent 1280x720  -format bmp -define bmp:format=bmp3 $out/logo720.bmp
        convert ${bootLogo} -resize 640x480   -gravity Center -extent 640x480   -format bmp -define bmp:format=bmp3 $out/logo480.bmp
      '';
    }).edk2-firmware;
  };

  mkFlashScript = { name, flashArgs ? null, dtbsDir ? null, postPatch ? "", partitionTemplate ? null }: let
    _flash-tools = (flash-tools.override { inherit dtbsDir; }).overrideAttrs (origAttrs: { postPatch = (origAttrs.postPatch or "") + postPatch; });
  in writeShellScript "flash-${name}" (''
    WORKDIR=$(mktemp -d)
    function on_exit() {
      rm -rf "$WORKDIR"
    }
    trap on_exit EXIT

    cp -r ${_flash-tools}/. "$WORKDIR"
    chmod -R u+w "$WORKDIR"
    cd "$WORKDIR"

    # Make nvidia's flash script happy by adding all this stuff to our PATH
    export PATH=${lib.makeBinPath _flash-tools.flashDeps}:$PATH

    export NO_ROOTFS=1
    export NO_RECOVERY_IMG=1

    ${lib.optionalString (partitionTemplate != null) "cp ${partitionTemplate} flash.xml"}
  '' + (if (flashArgs != null) then ''
    ./flash.sh ${lib.optionalString (partitionTemplate != null) "-c flash.xml"} $@ ${flashArgs}
  '' else ''
    ${runtimeShell}
  ''));

  prebuilt = callPackages ./prebuilt.nix { inherit debs; l4tVersion = version; };

  cudaPackages = callPackages ./cuda-packages.nix { inherit debs cudaVersion autoAddOpenGLRunpathHook prebuilt; };

  samples = callPackages ./samples.nix { inherit debs cudaVersion autoAddOpenGLRunpathHook prebuilt cudaPackages; };

  # Just for convenience. Unused
  unpackedDebs = pkgs.runCommand "unpackedDebs" { nativeBuildInputs = [ pkgs.dpkg ]; } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") debs.common)}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") debs.t234)}
  '';

in rec {
  # Just for convenience
  inherit bspSrc debs unpackedDebs;

  inherit cudaPackages samples;
  inherit flash-tools;

  kernel = callPackage ./kernel { inherit (prebuilt) l4t-xusb-firmware; };

  # TODO: Source packages. source_sync.sh from bspSrc
  # OPTEE
  #   nv-tegra.nvidia.com/tegra/optee-src/atf.git
  #   nv-tegra.nvidia.com/tegra/optee-src/nv-optee.git
  # GST plugins

  inherit mkFlashScript;

  # Generic flash script which contains the default NVIDIA devices without any patches
  flash-script = mkFlashScript { name = "generic"; };
  flash-orin-agx-devkit = mkFlashScript {
    name = "orin-agx-devkit";
    flashArgs = "jetson-agx-orin-devkit mmcblk0p1";
    # We don't flash the sdmmc with kernel/initrd/etc at all. Just let it be a
    # regular NixOS machine instead of having some weird partition structure.
    partitionTemplate = runCommand "flash.xml" {} ''
      sed -z \
        -E 's#<device[^>]*type="sdmmc_user"[^>]*>.*?</device>##' \
        <${bspSrc}/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml \
        >$out
    '';
  };
  flash-xavier-agx-devkit = mkFlashScript {
    name = "xavier-agx-devkit";
    flashArgs = "-c bootloader/t186ref/cfg/flash_t194_uefi_sdmmc_min.xml jetson-agx-xavier-devkit mmcblk0p1";
    # Remove unnecessary partitions to make it more like
    # flash_t194_uefi_sdmmc_min.xml, except also keep the A/B slots of
    # each partition
    partitionTemplate = let
      partitionsToRemove = [
        "kernel" "kernel-dtb" "reserved_for_chain_A_user"
        "kernel_b" "kernel-dtb_b" "reserved_for_chain_B_user"
        "RECNAME" "RECDTB-NAME" "RP1" "RP2" "RECROOTFS" # Recovery
        "esp" # L4TLauncher
      ];
    in runCommand "flash.xml" {} ''
      sed -z \
        -E 's#<partition[^>]*type="(${lib.concatStringsSep "|" partitionsToRemove})"[^>]*>.*?</partition>##' \
        <${bspSrc}/bootloader/t186ref/cfg/flash_t194_sdmmc.xml \
        >$out
    '';
  };
  flash-xavier-nx-devkit = mkFlashScript {
    name = "xavier-nx-devkit";
    flashArgs = "jetson-xavier-nx-devkit-qspi mmcblk0p1";
    partitionTemplate = "${bspSrc}/bootloader/t186ref/cfg/flash_l4t_t194_qspi_p3668.xml";
  };
  # xavier-nx-devkit-emmc.conf uses p3668-0001 (production SoM) device tree,
  # Since we manually specifify the partition config file, we don't actually
  # use the eMMC at all.
  flash-xavier-nx-prod = mkFlashScript {
    name = "xavier-nx-prod";
    flashArgs = "jetson-xavier-nx-devkit-emmc mmcblk0p1";
    partitionTemplate = "${bspSrc}/bootloader/t186ref/cfg/flash_l4t_t194_qspi_p3668.xml";
  };
}
// prebuilt
// callPackage ./edk2-firmware.nix { inherit edk2; }
