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
}:

let
  cfg = config.hardware.nvidia-jetpack;
  inherit (config.networking) hostName;

  # We need to grab some packages from the device's aarch64 package set.
  inherit (pkgs.nvidia-jetpack)
    chipId
    flashInitrd
    mkFlashScript
    ;

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

  # With either produce a standard flash script, which does variant detection,
  # or if there is only a single variant, will produce a script specialized to
  # that particular variant.
  mkFlashScriptAuto = if builtins.length cfg.firmware.variants == 1 then mkFlashCmdScript else (mkFlashScript nvidia-jetpack.flash-tools);

  # Generate a flash script using the built configuration options set in a NixOS configuration
  flashScript = writeShellApplication {
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
      '';
      flashArgs = [ "--rcm-boot" ] ++ cfg.flashScriptOverrides.flashArgs;
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
      text = ''
        ${mkRcmBootScript {
          kernelPath = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
          initrdPath = "${flashInitrd}/initrd";
          kernelCmdline = "console=ttyTCU0,115200";
          # During the initrd flash script, we upload two edk2 builds to the
          # board, one that is only used temporarily to boot into our
          # kernel/initrd to perform the flashing, and another one that is
          # persisted to the firmware storage medium for future booting. We
          # don't want to influence the boot order of the temporary edk2 since
          # this may cause that edk2 to boot from something other than our
          # intended flashing kernel/initrd combo (e.g. disk or network). Since
          # the edk2 build that we actually persist to the board is embedded in
          # the initrd used for flashing, we have the desired boot order (as
          # configured in nix) in there and is not affected dynamically during
          # the flashing procedure. NVIDIA ensures that when the device is
          # using RCM boot, only the boot mode named "boot.img" is used (see https://gist.github.com/jmbaur/1ca79436e69eadc0a38ec0b43b16cb2f#file-flash-sh-L1675).
          additionalDtbOverlays = lib.filter (path: (path.name or "") != "DefaultBootOrder.dtbo") cfg.flashScriptOverrides.additionalDtbOverlays;
        }}
        echo
        echo "Jetson device should now be flashing and will reboot when complete."
        echo "You may watch the progress of this on the device's serial port"
      '';
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
{ inherit flashScript initrdFlashScript fuseScript rcmBoot; }
