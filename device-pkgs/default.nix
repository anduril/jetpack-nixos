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
  mkRcmBootScript = { kernelPath, initrdPath, kernelCmdline }: mkFlashScriptAuto {
    preFlashCommands = ''
      cp ${kernelPath} kernel/Image
      cp ${initrdPath} bootloader/l4t_initrd.img

      export CMDLINE="${builtins.toString kernelCmdline}"
      export INITRD_IN_BOOTIMG="yes"
    '';
    flashArgs = [ "--rcm-boot" ] ++ cfg.flashScriptOverrides.flashArgs;
  };

  # Produces a script which boots into this NixOS system via RCM mode
  # TODO: This doesn't work currently because `rcmBoot` would need to be built
  # on x86_64, and the machine in `config` should be aarch64-linux
  rcmBoot = writeShellApplication {
    name = "rcmboot-nixos";
    text = mkRcmBootScript {
      # See nixpkgs nixos/modules/system/activatation/top-level.nix for standard usage of these paths
      kernelPath = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
      initrdPath = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
      kernelCmdline = "init=${config.system.build.toplevel}/init initrd=initrd ${toString config.boot.kernelParams}";
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
          kernelCmdline = "initrd=initrd console=ttyTCU0,115200";
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
