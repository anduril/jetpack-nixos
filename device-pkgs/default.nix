{ config, pkgs, kernel, ... }:

{ lib
, dtc
, gcc
, makeInitrd
, nvidia-jetpack
, openssl
, python3
, runCommand
, writeScript
, writeShellApplication
, buildPackages
, makeModulesClosure
}:

let
  cfg = config.hardware.nvidia-jetpack;
  hostName = config.networking.hostName;

  # Packages from the device's aarch64 package set
  inherit (pkgs.nvidia-jetpack)
    chipId
    flashInitrd
    l4tVersion
    mkFlashScript;

  inherit (cfg.flashScriptOverrides)
    flashArgs
    fuseArgs
    partitionTemplate;

  # Function to create flash command script for a single variant
  mkFlashCmdScript = args: let
    variant = if builtins.length cfg.firmware.variants != 1
      then throw "mkFlashCmdScript requires exactly one Jetson variant set in hardware.nvidia-jetpack.firmware.variants"
      else builtins.elemAt cfg.firmware.variants 0;

    flash-tools-flashcmd = runCommand "flash-tools-flashcmd" {
      inherit (cfg.firmware.secureBoot) requiredSystemFeatures;
    } ''
      export BOARDID=${variant.boardid}
      export BOARDSKU=${variant.boardsku}
      export FAB=${variant.fab}
      export BOARDREV=${variant.boardrev}
      ${lib.optionalString (variant.chipsku != null) ''
        export CHIP_SKU=${variant.chipsku}
      ''}
      export CHIPREV=${variant.chiprev}
      ${lib.optionalString (variant.ramcode != null) ''
        export RAMCODE=${variant.ramcode}
      ''}

      ${cfg.firmware.secureBoot.preSignCommands buildPackages}

      ${mkFlashScript nvidia-jetpack.flash-tools (args // {
        # kernel = kernel;
        flashArgs = [ "--no-root-check" "--no-flash" ] ++ (args.flashArgs or flashArgs);
      })}

      cp -r ./ $out
    '';
  in
    (import ./flashcmd-script.nix) {
      inherit lib gcc dtc;
      flash-tools = flash-tools-flashcmd;
    };

  # Function to automatically choose the appropriate flash script
  mkFlashScriptAuto = args:
    if builtins.length cfg.firmware.variants == 1
    then mkFlashCmdScript args
    else mkFlashScript nvidia-jetpack.flash-tools args;

  # Function to create RCM boot script
  mkRcmBootScript = { kernelPath, initrdPath, kernelCmdline }: mkFlashScriptAuto {
    # kernel = kernel;
    preFlashCommands = ''
      cp ${kernel}/Image kernel/Image
      cp ${initrdPath}/initrd bootloader/l4t_initrd.img

      echo "Kernel: ${kernel}"
      echo "Initrd Path: ${initrdPath}"

      export CMDLINE="${builtins.toString kernelCmdline}"
      export INITRD_IN_BOOTIMG="yes"
    '';
    flashArgs = [ "--rcm-boot" ] ++ cfg.flashScriptOverrides.flashArgs;
  };

  # Generate the main flash script
  flashScript = writeShellApplication {
    name = "flash-${hostName}";
    text = mkFlashScriptAuto { };
    meta.platforms = [ "x86_64-linux" ];
  };

  # Generate RCM boot script
  rcmBoot = writeShellApplication {
    name = "rcmboot-nixos";
    text = mkRcmBootScript {
      kernelPath = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
      initrdPath = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
      kernelCmdline = "init=${config.system.build.toplevel}/init initrd=initrd ${toString config.boot.kernelParams}";
    };
    meta.platforms = [ "x86_64-linux" ];
  };

  # Generate signed firmware
  signedFirmware = runCommand "signed-${hostName}-${l4tVersion}" {
    inherit (cfg.firmware.secureBoot) requiredSystemFeatures;
  } (mkFlashScript nvidia-jetpack.flash-tools {
    # kernel = kernel;
    flashCommands = ''
      ${cfg.firmware.secureBoot.preSignCommands buildPackages}
    '' + lib.concatMapStringsSep "\n" (v: with v; ''
      BOARDID=${boardid} BOARDSKU=${boardsku} FAB=${fab} BOARDREV=${boardrev} FUSELEVEL=${fuselevel} CHIPREV=${chiprev} ${lib.optionalString (chipsku != null) "CHIP_SKU=${chipsku}"} ${lib.optionalString (ramcode != null) "RAMCODE=${ramcode}"} ./flash.sh ${lib.optionalString (partitionTemplate != null) "-c flash.xml"} --no-root-check --no-flash --sign ${builtins.toString flashArgs}

      outdir=$out/${boardid}-${fab}-${boardsku}-${boardrev}-${if fuselevel == "fuselevel_production" then "1" else "0"}-${chiprev}
      mkdir -p $outdir

      cp -v bootloader/signed/flash.idx $outdir/

      # Copy files referenced by flash.idx
      while IFS=", " read -r _ _ _ _ partfile _ _; do
        if [[ "$partfile" != "" ]]; then
          if [[ -f "bootloader/signed/$partfile" ]]; then
            cp -v "bootloader/signed/$partfile" $outdir/
          elif [[ -f "bootloader/$partfile" ]]; then
            cp -v "bootloader/$partfile" $outdir/
          else
            echo "Unable to find $partfile"
            exit 1
          fi
        fi
      done < bootloader/signed/flash.idx

      rm -rf bootloader/signed
    '') cfg.firmware.variants;
  });

  # Generate initrd flash script
  initrdFlashScript = writeShellApplication {
    name = "initrd-flash-${hostName}";
    text = ''
      ${mkRcmBootScript {
        # kernel = kernel;
        kernelPath = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
        initrdPath = let
          signedFirmwareInitrd = makeInitrd {
            contents = [{ object = signedFirmware; symlink = "/signed-firmware"; }];
          };
        in
          runCommand "combined-initrd" { } ''
            cat ${flashInitrd}/initrd ${signedFirmwareInitrd}/initrd > $out
          '';
        kernelCmdline = "initrd=initrd console=ttyTCU0,115200";
      }}
      echo
      echo "Jetson device should now be flashing and will reboot when complete."
      echo "You may watch the progress of this on the device's serial port"
      echo "#######################################################################"
      echo "Kernel: ${config.boot.kernelPackages.kernel}"
      echo "#######################################################################"
    '';
    meta.platforms = [ "x86_64-linux" ];
  };

  # Generate fuse script
  fuseScript = writeShellApplication {
    name = "fuse-${hostName}";
    text = (import ./flash-script.nix) {
      inherit lib;
      inherit (nvidia-jetpack) flash-tools;
      flashCommands = ''
        ./odmfuse.sh -i ${chipId} "$@" ${builtins.toString fuseArgs}
      '';
      dtbsDir = config.hardware.deviceTree.package;
    };
    meta.platforms = [ "x86_64-linux" ];
  };

in
{
  inherit
    flashScript
    fuseScript
    initrdFlashScript
    mkFlashCmdScript
    mkFlashScriptAuto
    mkRcmBootScript
    rcmBoot
    signedFirmware;
}
