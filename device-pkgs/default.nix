{ lib, callPackage, runCommand, writeScript, writeShellApplication, makeInitrd, makeModulesClosure,
  flashFromDevice, edk2-jetson, uefi-firmware, flash-tools, buildTOS, buildOpteeTaDevKit, opteeClient,
  python3, openssl_1_1, dtc,

  l4tVersion,
  pkgsAarch64,
}:

config:

let
  cfg = config.hardware.nvidia-jetpack;
  hostName = config.networking.hostName;

  socType = if cfg.som == null then null
    else if lib.hasPrefix "orin-" cfg.som then "t234"
    else if lib.hasPrefix "xavier-" cfg.som then "t194"
    else throw "Unknown SoC type";

  inherit (cfg.flashScriptOverrides)
    flashArgs fuseArgs partitionTemplate;

  flash-tools-patched = flash-tools.overrideAttrs ({ patches ? [], postPatch ? "", ... }: {
    patches = patches ++ cfg.flashScriptOverrides.patches;
    postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
  });

  tosArgs = {
    inherit socType;
    inherit (cfg.firmware.optee) taPublicKeyFile;
    opteePatches = cfg.firmware.optee.patches;
    extraMakeFlags = cfg.firmware.optee.extraMakeFlags;
  };
  tosImage = buildTOS tosArgs;
  taDevKit = buildOpteeTaDevKit tosArgs;

  teeSupplicant = opteeClient.overrideAttrs (old: {
    pname = "tee-supplicant";
    buildFlags = (old.buildFlags or []) ++ [ "CFG_TEE_CLIENT_LOAD_PATH=${cfg.firmware.optee.clientLoadPath}" ];
    # remove unneeded headers
    postInstall = ''
      rm -rf $out/include
    '';
  });

  # TODO: Unify with fuseScript below
  mkFlashScript = args: import ./flash-script.nix ({
    inherit lib flashArgs partitionTemplate;

    inherit (cfg.flashScriptOverrides) additionalDtbOverlays;

    flash-tools = flash-tools-patched;

    uefi-firmware = uefi-firmware.override ({
      bootLogo = cfg.firmware.uefi.logo;
      debugMode = cfg.firmware.uefi.debugMode;
      errorLevelInfo = cfg.firmware.uefi.errorLevelInfo;
      edk2NvidiaPatches = cfg.firmware.uefi.edk2NvidiaPatches;
    } // lib.optionalAttrs cfg.firmware.uefi.capsuleAuthentication.enable {
      inherit (cfg.firmware.uefi.capsuleAuthentication) trustedPublicCertPemFile;
    });

    inherit socType;

    inherit tosImage;
    eksFile = cfg.firmware.eksFile;

    dtbsDir = config.hardware.deviceTree.package;
  } // args);

  # This produces a script where we have already called the ./flash.sh script
  # with `--no-flash` and produced a file under bootloader/flashcmd.txt.
  # This requires setting various BOARD* environment variables to the exact
  # board being flashed. These are set by the firmware.variants option.
  #
  # The output of this should be something we can take anywhere and doesn't
  # require any additional signing or other dynamic behavior
  mkFlashCmdScript = args: let
    variant =
      if builtins.length cfg.firmware.variants != 1
      then throw "mkFlashCmdScript requires exactly one Jetson variant set in hardware.nvidia-jetson.firmware.variants"
      else builtins.elemAt cfg.firmware.variants 0;

    # Use the flash-tools produced by mkFlashScript, we need whatever changes
    # the script made, as well as the flashcmd.txt from it
    flash-tools-flashcmd = runCommand "flash-tools-flashcmd" {
      # Needed for signing
      inherit (cfg.firmware.secureBoot) requiredSystemFeatures;
    } ''
      export BOARDID=${variant.boardid}
      export BOARDSKU=${variant.boardsku}
      export FAB=${variant.fab}
      export BOARDREV=${variant.boardrev}
      export CHIP_SKU=${variant.chiprev}

      ${cfg.firmware.secureBoot.preSignCommands}

      ${mkFlashScript (args // { flashArgs = [ "--no-root-check" "--no-flash" ] ++ (args.flashArgs or flashArgs); }) }

      cp -r ./ $out
    '';
    # TODO: Do we also need these? Set in l4t_create_images_for_kernel_flash.sh
    # export RAMCODE_ID
    # export RAMCODE
  in import ./flashcmd-script.nix {
    inherit lib;
    flash-tools = flash-tools-flashcmd;
  };

  # With either produce a standard flash script, which does variant detection,
  # or if there is only a single variant, will produce a script specialized to
  # that particular variant.
  mkFlashScriptAuto = if builtins.length cfg.firmware.variants == 1 then mkFlashCmdScript else mkFlashScript;

  # Generate a flash script using the built configuration options set in a NixOS configuration
  flashScript = writeShellApplication {
    name = "flash-${hostName}";
    text = (mkFlashScriptAuto {});
  };

  # Produces a script that boots a given kernel, initrd, and cmdline using the RCM boot method
  mkRcmBootScript = { kernelPath, initrdPath, kernelCmdline }: writeShellApplication {
    name = "rcm-boot";
    text = mkFlashScriptAuto {
      preFlashCommands = ''
        cp ${kernelPath} kernel/Image
        cp ${initrdPath}/initrd bootloader/l4t_initrd.img

        export CMDLINE="${lib.escapeShellArgs kernelCmdline}"
        export INITRD_IN_BOOTIMG="yes"
      '';
      flashArgs = [ "--rcm-boot" ] ++ cfg.flashScriptOverrides.flashArgs;
    };
  };

  # Produces a script which boots into this NixOS system via RCM mode
  # TODO: This doesn't work currently because `rcmBoot` would need to be built
  # on x86_64, and the machine in `config` should be aarch64-linux
  rcmBoot = mkRcmBootScript {
    # See nixpkgs nixos/modules/system/activatation/top-level.nix for standard usage of these paths
    kernelPath = "${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}";
    initrdPath = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
    kernelCmdline = "init=${config.system.build.toplevel}/init initrd=initrd ${toString config.boot.kernelParams}";
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
      contents = [
        { object = jetpack-init; symlink = "/init"; }
        { object = "${modulesClosure}/lib/modules"; symlink = "/lib/modules"; }
        { object = "${modulesClosure}/lib/firmware"; symlink = "/lib/firmware"; }
      ];
    };
  in writeShellApplication {
    name = "initrd-flash-${hostName}";
    text = ''
      ${mkRcmBootScript {
        kernelPath = "${config.boot.kernelPackages.kernel}/Image";
        initrdPath = initrd;
        kernelCmdline = "initrd=initrd console=ttyTCU0,115200";
      }}
      echo
      echo "Jetson device should now be flashing and will reboot when complete."
      echo "You may watch the progress of this on the device's serial port"
    '';
  };

  signedFirmware = runCommand "signed-${hostName}-${l4tVersion}" {
    inherit (cfg.firmware.secureBoot) requiredSystemFeatures;
  } (mkFlashScript {
    flashCommands = cfg.firmware.secureBoot.preSignCommands + lib.concatMapStringsSep "\n" (v: with v; ''
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
    '') cfg.firmware.variants;
  });

  # Bootloader Update Package (BUP)
  # TODO: Maybe generate this ourselves from signedFirmware so we dont have multiple scripts using the same keys to sign the same artifacts
  bup = runCommand "bup-${hostName}-${l4tVersion}" {
    inherit (cfg.firmware.secureBoot) requiredSystemFeatures;
  } ((mkFlashScript {
    # TODO: Remove preSignCommands when we switch to using signedFirmware directly
    flashCommands = cfg.firmware.secureBoot.preSignCommands + lib.concatMapStringsSep "\n" (v: with v;
      "BOARDID=${boardid} BOARDSKU=${boardsku} FAB=${fab} BOARDREV=${boardrev} FUSELEVEL=${fuselevel} CHIPREV=${chiprev} ./flash.sh ${lib.optionalString (partitionTemplate != null) "-c flash.xml"} --no-flash --bup --multi-spec ${builtins.toString flashArgs}"
    ) cfg.firmware.variants;
  }) + ''
    mkdir -p $out
    cp -r bootloader/payloads_*/* $out/
  '');

  # See l4t_generate_soc_bup.sh
  # python ${edk2-jetson}/BaseTools/BinWrappers/PosixLike/GenerateCapsule -v --encode --monotonic-count 1
  # NOTE: providing null public certs here will use the test certs in the EDK2 repo
  uefiCapsuleUpdate = runCommand "uefi-${hostName}-${l4tVersion}.Cap" {
    nativeBuildInputs = [ python3 openssl_1_1 ];
    inherit (cfg.firmware.uefi.capsuleAuthentication) requiredSystemFeatures;
  } (''
    ${cfg.firmware.uefi.capsuleAuthentication.preSignCommands}
    bash ${flash-tools-patched}/generate_capsule/l4t_generate_soc_capsule.sh \
  '' + (lib.optionalString cfg.firmware.uefi.capsuleAuthentication.enable ''
      --trusted-public-cert ${cfg.firmware.uefi.capsuleAuthentication.trustedPublicCertPemFile} \
      --other-public-cert ${cfg.firmware.uefi.capsuleAuthentication.otherPublicCertPemFile} \
      --signer-private-cert ${cfg.firmware.uefi.capsuleAuthentication.signerPrivateCertPemFile} \
    '') + ''
      -i ${bup}/bl_only_payload \
      -o $out \
      ${socType}
  '');

  fuseScript = writeShellApplication {
    name = "fuse-${hostName}";
    text = import ./fuse-script.nix {
      inherit lib;
      flash-tools = flash-tools-patched;
      inherit fuseArgs;

      chipId = if cfg.som == null then null
        else if lib.hasPrefix "orin-" cfg.som then "0x23"
        else if lib.hasPrefix "xavier-" cfg.som then "0x19"
        else throw "Unknown SoC type";
    };
  };
in {
  inherit (tosImage) nvLuksSrv hwKeyAgent;
  inherit mkFlashScript mkFlashCmdScript mkFlashScriptAuto;
  inherit flashScript initrdFlashScript tosImage taDevKit teeSupplicant signedFirmware bup fuseScript uefiCapsuleUpdate;
  inherit mkRcmBootScript rcmBoot;
}
