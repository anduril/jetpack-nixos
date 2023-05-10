{ lib, callPackage, runCommand, writeScript, writeShellApplication, makeInitrd, makeModulesClosure,
  flashFromDevice, edk2-jetson, uefi-firmware, flash-tools, buildTOS,
  python3, bspSrc, openssl,
  l4tVersion,
  pkgsAarch64,
}:

config:

let
  # These are from l4t_generate_soc_bup.sh, plus some additional ones found in the wild.
  variants = rec {
    xavier-agx = [
      { boardid="2888"; boardsku="0001"; fab="400"; boardrev="D.0"; fuselevel="fuselevel_production"; chiprev="2"; }
      { boardid="2888"; boardsku="0001"; fab="400"; boardrev="E.0"; fuselevel="fuselevel_production"; chiprev="2"; }
      { boardid="2888"; boardsku="0004"; fab="400"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; }
      { boardid="2888"; boardsku="0005"; fab="402"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; }
    ];
    xavier-nx = [ # Dev variant
      { boardid="3668"; boardsku="0000"; fab="100"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; }
      { boardid="3668"; boardsku="0000"; fab="301"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; }
    ];
    xavier-nx-emmc = [ # Prod variant
      { boardid="3668"; boardsku="0001"; fab="100"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; }
      { boardid="3668"; boardsku="0003"; fab="301"; boardrev=""; fuselevel="fuselevel_production"; chiprev="2"; }
    ];

    orin-agx = [
      { boardid="3701"; boardsku="0000"; fab="300"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; }
      { boardid="3701"; boardsku="0004"; fab="300"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # 32GB
      { boardid="3701"; boardsku="0005"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # 64GB
    ];

    orin-nano = [
      { boardid = "3767"; boardsku = "0000"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # Orin NX 16GB
      { boardid = "3767"; boardsku = "0001"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # Orin NX 8GB
      { boardid = "3767"; boardsku = "0003"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # Orin Nano 8GB
      { boardid = "3767"; boardsku = "0005"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } #
      { boardid = "3767"; boardsku = "0004"; fab="000"; boardrev=""; fuselevel="fuselevel_production"; chiprev=""; } # Orin Nano 4GB
    ];
    orin-nx = orin-nano;
  };

  cfg = config.hardware.nvidia-jetpack;
  hostName = config.networking.hostName;

  socType =
    if lib.hasPrefix "orin-" cfg.som then "t234"
    else if lib.hasPrefix "xavier-" cfg.som then "t194"
    else throw "Unknown SoC type";

  inherit (cfg.flashScriptOverrides)
    flashArgs partitionTemplate;

  tosImage = buildTOS { inherit socType; };

  mkFlashScript = args: import ./flash-script.nix ({
    inherit lib flashArgs partitionTemplate;

    flash-tools = flash-tools.overrideAttrs ({ postPatch ? "", ... }: {
      postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
    });

    uefi-firmware = uefi-firmware.override {
      bootLogo = cfg.bootloader.logo;
      debugMode = cfg.bootloader.debugMode;
      errorLevelInfo = cfg.bootloader.errorLevelInfo;
      edk2NvidiaPatches = cfg.bootloader.edk2NvidiaPatches;
    };

    inherit tosImage;

    dtbsDir = config.hardware.deviceTree.package;
  } // args);

  # Generate a flash script using the built configuration options set in a NixOS configuration
  flashScript = writeShellApplication {
    name = "flash-${hostName}";
    text = (mkFlashScript {});
  };

  # TODO: The flash script should not have the kernel output in its runtime closure
  initrdFlashScript = let
    modules = [ "qspi_mtd" "spi_tegra210_qspi" "at24" "spi_nor" ];
    modulesClosure = makeModulesClosure {
      rootModules = modules;
      kernel = config.system.modulesTree;
      firmware = config.hardware.firmware;
      allowMissing = false;
    };
    jetpack-init = writeScript "init" ''
      #!${pkgsAarch64.pkgsStatic.busybox}/bin/sh
      export PATH=${pkgsAarch64.pkgsStatic.busybox}/bin
      mkdir -p /proc /dev /sys
      mount -t proc proc -o nosuid,nodev,noexec /proc
      mount -t devtmpfs none -o nosuid /dev
      mount -t sysfs sysfs -o nosuid,nodev,noexec /sys

      for mod in ${builtins.toString modules}; do
        modprobe -v $mod
      done

      if ${flashFromDevice}/bin/${flashFromDevice.name} ${signedFirmware}; then
        echo "Flashing platform firmware successful. Rebooting now."
        sync
        reboot -f
      else
        echo "Flashing platform firmware unsuccessful. Entering console"
        exec ${pkgsAarch64.pkgsStatic.busybox}/bin/sh
      fi
    '';
    initrd = makeInitrd {
      contents = let
        kernel = config.boot.kernelPackages.kernel;
      in [
        { object = jetpack-init; symlink = "/init"; }
        { object = "${modulesClosure}/lib/modules"; symlink = "/lib/modules"; }
        { object = "${modulesClosure}/lib/firmware"; symlink = "/lib/firmware"; }
      ];
    };
  in writeShellApplication {
    name = "initrd-flash-${hostName}";
    text = mkFlashScript {
      preFlashCommands = ''
        cp ${config.boot.kernelPackages.kernel}/Image kernel/Image
        cp ${initrd}/initrd bootloader/l4t_initrd.img

        export CMDLINE="initrd=initrd console=ttyTCU0,115200"
        export INITRD_IN_BOOTIMG="yes"
      '';
      flashArgs = [ "--rcm-boot" ] ++ cfg.flashScriptOverrides.flashArgs;
      postFlashCommands = ''
        echo
        echo "Jetson device should now be flashing and will reboot when complete."
        echo "You may watch the progress of this on the device's serial port"
      '';
    };
  };

  # This must be built on x86_64-linux
  signedFirmware = runCommand "signed-${hostName}-${l4tVersion}" {} (mkFlashScript {
    flashCommands = lib.concatMapStringsSep "\n" (v: with v; ''
      BOARDID=${boardid} BOARDSKU=${boardsku} FAB=${fab} BOARDREV=${boardrev} FUSELEVEL=${fuselevel} CHIPREV=${chiprev} ./flash.sh ${lib.optionalString (partitionTemplate != null) "-c flash.xml"} --no-root-check --no-flash --sign ${builtins.toString flashArgs}

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
    '') variants.${cfg.som};
  });

  # Bootloader Update Package (BUP)
  # TODO: Try to make this run on aarch64-linux?
  # TODO: Maybe generate this ourselves from signedFirmware so we dont have multiple scripts using the same keys to sign the same artifacts
  bup = runCommand "bup-${hostName}-${l4tVersion}" {} ((mkFlashScript {
    flashCommands = let
    in lib.concatMapStringsSep "\n" (v: with v;
      "BOARDID=${boardid} BOARDSKU=${boardsku} FAB=${fab} BOARDREV=${boardrev} FUSELEVEL=${fuselevel} CHIPREV=${chiprev} ./flash.sh ${lib.optionalString (partitionTemplate != null) "-c flash.xml"} --no-flash --bup --multi-spec ${builtins.toString flashArgs}"
    ) variants.${cfg.som};
  }) + ''
    mkdir -p $out
    cp -r bootloader/payloads_*/* $out/
  '');

  # TODO: This step could probably also be done on aarch64-linux too.  That would be valuable to allow Jetsons to be able to update themselves.
  # See l4t_generate_soc_bup.sh
  # python ${edk2-jetson}/BaseTools/BinWrappers/PosixLike/GenerateCapsule -v --encode --monotonic-count 1
  # ${bspSrc}
  # TODO: improve soc arch (t234) condition
  uefiCapsuleUpdate = runCommand "uefi-${hostName}-${l4tVersion}.Cap" { nativeBuildInputs = [ python3 openssl ]; } ''
    bash ${bspSrc}/generate_capsule/l4t_generate_soc_capsule.sh -i ${bup}/bl_only_payload -o $out ${socType}
  '';
in {
  inherit (tosImage) nvLuksSrv hwKeyAgent;
  inherit flashScript initrdFlashScript tosImage signedFirmware bup uefiCapsuleUpdate;
}
