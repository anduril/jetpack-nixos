# These come from the device's nixos module arguments, so `pkgs` is actually an
# aarch64 hostPlatform packaget-set.
{ config, pkgs, kernel,  ... }:

# These must be filled in by a `callPackage` from an x86_64 hostPlatform
# package-set to satisfy being able to run nvidia's prebuilt binaries on an
# x86-compatible platform.
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
# possibly need clean up with imports below
, makeModulesClosure
}:

let
  cfg = config.hardware.nvidia-jetpack;
  inherit (config.networking) hostName;

  # We need to grab some packages from the device's aarch64 package set.
  inherit (pkgs.nvidia-jetpack)
    chipId
    flashInitrd
    l4tVersion
    mkFlashScript
    ;

  inherit (cfg.flashScriptOverrides) flashArgs fuseArgs partitionTemplate;

  # This produces a script where we have already called the ./flash.sh script
  # with `--no-flash` and produced a file under bootloader/flashcmd.txt.
  # This requires setting various BOARD* environment variables to the exact
  # board being flashed. These are set by the firmware.variants option.
  #
  # The output of this should be something we can take anywhere and doesn't
  # require any additional signing or other dynamic behavior
  mkFlashCmdScript = args:
    let
      variant =
        if builtins.length cfg.firmware.variants != 1
        then throw "mkFlashCmdScript requires exactly one Jetson variant set in hardware.nvidia-jetson.firmware.variants"
        else builtins.elemAt cfg.firmware.variants 0;

      # Use the flash-tools produced by mkFlashScript, we need whatever changes
      # the script made, as well as the flashcmd.txt from it
      flash-tools-flashcmd = runCommand "flash-tools-flashcmd"
        {
          # Needed for signing
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

        ${mkFlashScript nvidia-jetpack.flash-tools (args // { flashArgs = [ "--no-root-check" "--no-flash" ] ++ (args.flashArgs or flashArgs); }) }

     
        cp -r ./ $out
      '';
    in
    builtins.trace "-----------------------------MKFLASHSCRIPT------------------------------------" null
    import ./flashcmd-script.nix {
      inherit lib;
      inherit gcc dtc;
      flash-tools = flash-tools-flashcmd;
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
      cp ${kernel}/Image kernel/Image
      cp ${initrdPath}/initrd bootloader/l4t_initrd.img
       

      echo @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
      echo ${kernel} ${initrdPath}
      echo @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

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
          initrdPath =
            let
              signedFirmwareInitrd = makeInitrd {
                contents = [{ object = signedFirmware; symlink = "/signed-firmware"; }];
              };
            in
            # The linux kernel supports concatenated initrds where each initrd
            # can be optionally compressed with any compression algorithm
            # supported by the kernel (initrds don't need to match in
            # compression algorithm).
            runCommand "combined-initrd" { } ''
              cat ${flashInitrd}/initrd ${signedFirmwareInitrd}/initrd > $out
            '';
          kernelCmdline = "initrd=initrd console=ttyTCU0,115200";
        }}
        echo
        echo "Jetson device should now be flashing and will reboot when complete."
        echo "You may watch the progress of this on the device's serial port"
        echo "#######################################################################"
        echo "#######################################################################"
        echo " ${config.boot.kernelPackages.kernel}"
        echo "#######################################################################"
        echo "#######################################################################"

      '';
      meta.platforms = [ "x86_64-linux" ];
    };

  signedFirmware = runCommand "signed-${hostName}-${l4tVersion}"
    {
      inherit (cfg.firmware.secureBoot) requiredSystemFeatures;
    }
    (mkFlashScript nvidia-jetpack.flash-tools {
      flashCommands = ''
        ${cfg.firmware.secureBoot.preSignCommands buildPackages}
      '' + lib.concatMapStringsSep "\n"
        (v: with v; ''
          BOARDID=${boardid} BOARDSKU=${boardsku} FAB=${fab} BOARDREV=${boardrev} FUSELEVEL=${fuselevel} CHIPREV=${chiprev} ${lib.optionalString (chipsku != null) "CHIP_SKU=${chipsku}"} ${lib.optionalString (ramcode != null) "RAMCODE=${ramcode}"} ./flash.sh ${lib.optionalString (partitionTemplate != null) "-c flash.xml"} --no-root-check --no-flash --sign ${builtins.toString flashArgs}

          outdir=$out/${boardid}-${fab}-${boardsku}-${boardrev}-${if fuselevel == "fuselevel_production" then "1" else "0"}-${chiprev}--
          mkdir -p $outdir

          cp -v bootloader/signed/flash.idx $outdir/

          # Copy files referenced by flash.idx
          while IFS=", " read -r partnumber partloc start_location partsize partfile partattrs partsha; do
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
        '')
        cfg.firmware.variants;
    });

  fuseScript = writeShellApplication {
    name = "fuse-${hostName}";
    text = import ./flash-script.nix {
      inherit lib;
      inherit (nvidia-jetpack) flash-tools;
      flashCommands = ''
        ./odmfuse.sh -i ${chipId} "$@" ${builtins.toString fuseArgs}
      '';

      # Fuse script needs device tree files, which aren't already present for
      # non-devkit boards, so we need to get our built version of them
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
    signedFirmware
    ;
}
