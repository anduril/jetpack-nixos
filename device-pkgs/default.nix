# These come from the device's nixos module arguments, so `pkgs` is actually an
# aarch64 hostPlatform packaget-set.
{ config, pkgs, ... }:

# These must be filled in by a `callPackage` from an x86_64 hostPlatform
# package-set to satisfy being able to run nvidia's prebuilt binaries on an
# x86-compatible platform.
{ lib
, dtc
, gcc
, nvidia-jetpack
, writeShellApplication
, buildPackages
, writeText
, deviceTree
, tio
, expect
}:

let
  cfg = config.hardware.nvidia-jetpack;
  inherit (config.networking) hostName;

  # We need to grab some packages from the device's aarch64 package set.
  inherit (pkgs.nvidia-jetpack)
    chipId
    flashInitrd
    mkFlashScript
    l4tMajorMinorPatchVersion
    ;

  jetpackAtLeast = lib.versionAtLeast cfg.majorVersion;
  jetpackOlder = lib.versionOlder cfg.majorVersion;

  # This produces a script where we have already called the ./flash.sh script
  # with `--no-flash` and produced a file under bootloader/flashcmd.txt.
  # This requires setting various BOARD* environment variables to the exact
  # board being flashed. These are set by the firmware.variants option.
  #
  # The output of this should be something we can take anywhere and doesn't
  # require any additional signing or other dynamic behavior
  mkFlashCmdScript = args: import ./flashcmd-script.nix {
    inherit lib;
    inherit gcc dtc;
    flash-tools = nvidia-jetpack.flash-tools-flashcmd.override {
      inherit mkFlashScript;
      mkFlashScriptArgs = args;
    };
  };

  # Inside a Nix derivation (sandboxed), call the flash.sh scripts and others
  # to produce a flashcmd.txt that will be run directly. This removes most of
  # the dynamism available to the flash script and requires specifying many
  # more environment variables which are normally autodetected
  useFlashCmd = builtins.length cfg.firmware.variants == 1;

  # With either produce a standard flash script, which does variant detection,
  # or if there is only a single variant, will produce a script specialized to
  # that particular variant.
  mkFlashScriptAuto = if useFlashCmd then mkFlashCmdScript else (mkFlashScript nvidia-jetpack.flash-tools);

  # Generate a flash script using the built configuration options set in a NixOS configuration
  legacyFlashScript = writeShellApplication {
    name = "flash-${hostName}";
    text = (mkFlashScriptAuto { });
    meta.platforms = [ "x86_64-linux" ];
  };

  # Produces a script that boots a given kernel, initrd, and cmdline using the RCM boot method
  mkRcmBootScript = { kernelPath, initrdPath, kernelCmdline, ... }@args: mkFlashScriptAuto (
    builtins.removeAttrs args [ "kernelPath" "initrdPath" "kernelCmdline" ] // {
      preFlashCommands = ''
        cp ${kernelPath} kernel/Image
        cp ${initrdPath} bootloader/l4t_initrd.img

        export CMDLINE="${builtins.toString kernelCmdline}"
        export INITRD_IN_BOOTIMG="yes"
      '' + lib.optionalString (cfg.firmware.secureBoot.pkcFile != null) ''
        # If secure boot is enabled, nvidia requires the kernel to be signed
        (
          ${cfg.firmware.secureBoot.preSignCommands buildPackages}
          # See l4t_uefi_sign_image.sh from BSP, or tools/README_uefi_secureboot.txt
          # This is not good
          bash ./l4t_uefi_sign_image.sh --image ./kernel/Image --cert ${cfg.firmware.uefi.secureBoot.signer.cert} --key ${cfg.firmware.uefi.secureBoot.signer.key} --mode nosplit
        )
      '';

      flashArgs =
        [ "--rcm-boot" ]
        # JetPack 7 wants to rebuild system.img with rootfs by default, we don't want that
        ++ lib.optional (jetpackAtLeast "7") "-r"
        # A little jank, but don't have the flash script itself actually flash, just produce the flashcmd.txt file
        # We need to sign the boot.img file afterwards in this script
        ++ lib.optional (cfg.firmware.secureBoot.pkcFile != null) "--no-flash"
        ++ cfg.flashScriptOverrides.flashArgs;

      postFlashCommands = lib.optionalString (cfg.firmware.secureBoot.pkcFile != null) ''
        (
          # If secure boot is enabled, the boot.img needs to be signed.
          cd bootloader
          ${cfg.firmware.secureBoot.preSignCommands buildPackages}
          # See l4t_uefi_sign_image.sh from BSP, or tools/README_uefi_secureboot.txt
          bash ../l4t_uefi_sign_image.sh --image boot.img --cert ${cfg.firmware.uefi.secureBoot.signer.cert} --key ${cfg.firmware.uefi.secureBoot.signer.key} --mode append
        )
      '' + lib.optionalString (!useFlashCmd && cfg.firmware.secureBoot.pkcFile != null) ''
        (
          # Now execute flash
          echo "Flashing device now"
          cd bootloader; bash ./flashcmd.txt
        )
      '';
    }
  );

  # Produces a script which boots into this NixOS system via RCM mode
  rcmBoot = writeShellApplication {
    name = "rcmboot-nixos";
    text = mkRcmBootScript {
      # See nixpkgs nixos/modules/system/activatation/top-level.nix for standard usage of these paths
      kernelPath = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
      initrdPath = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
      kernelCmdline = "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}";
    };
    meta.platforms = [ "x86_64-linux" ];
  };

  # TODO: The flash script should not have the kernel output in its runtime closure
  initrdFlashScript =
    writeShellApplication {
      name = "initrd-flash-${hostName}";
      text = import ./initrdflash-script.nix { inherit mkRcmBootScript config flashInitrd lib l4tMajorMinorPatchVersion writeText deviceTree tio expect; };
      meta.platforms = [ "x86_64-linux" ];
    };

  fuseScript = writeShellApplication {
    name = "fuse-${hostName}";
    text = import ./flash-script.nix {
      inherit lib;
      inherit (nvidia-jetpack) flash-tools;
      flashCommands = ''
        ./odmfuse.sh -i ${chipId} "$@" ${builtins.toString cfg.flashScriptOverrides.fuseArgs}
      '';

      # Fuse script needs device tree files, which aren't already present for
      # non-devkit boards, so we need to get our built version of them
      dtbsDir = config.hardware.deviceTree.package;
    };
    meta.platforms = [ "x86_64-linux" ];
  };
in
{ inherit initrdFlashScript legacyFlashScript fuseScript rcmBoot; flashScript = initrdFlashScript; }
