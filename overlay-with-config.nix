# device-specific packages that are influenced by the nixos config
config:

let
  inherit (config.networking) hostName;
in

final: prev: (
  let
    cfg = config.hardware.nvidia-jetpack;

    inherit (final) lib;

    flashTools = cfg.flasherPkgs.callPackages (import ./device-pkgs { inherit config; pkgs = final; }) { };
  in
  {
    nvidia-jetpack = prev.nvidia-jetpack.overrideScope (finalJetpack: prevJetpack: {
      socType =
        if cfg.som == null then null
        else if lib.hasPrefix "orin-" cfg.som then "t234"
        else if lib.hasPrefix "xavier-" cfg.som then "t194"
        else throw "Unknown SoC type";

      chipId =
        if cfg.som == null then null
        else if lib.hasPrefix "orin-" cfg.som then "0x23"
        else if lib.hasPrefix "xavier-" cfg.som then "0x19"
        else throw "Unknown SoC type";

      otaUtils = prevJetpack.otaUtils.override {
        inherit (config.boot.loader.efi) efiSysMountPoint;
      };

      edk2NvidiaSrc = (prevJetpack.edk2NvidiaSrc.override {
        errorLevelInfo = cfg.firmware.uefi.errorLevelInfo;
        bootLogo = cfg.firmware.uefi.logo;
      }).overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ cfg.firmware.uefi.edk2NvidiaPatches;
      });

      jetsonEdk2Uefi = (prevJetpack.jetsonEdk2Uefi.override ({
        debugMode = cfg.firmware.uefi.debugMode;
      } // lib.optionalAttrs cfg.firmware.uefi.capsuleAuthentication.enable {
        inherit (cfg.firmware.uefi.capsuleAuthentication) trustedPublicCertPemFile;
      })).overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ cfg.firmware.uefi.edk2UefiPatches;
      });

      opteeOS = prevJetpack.opteeOS.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ cfg.firmware.optee.patches;
        makeFlags = (old.makeFlags or [ ]) ++ cfg.firmware.optee.extraMakeFlags;
      });

      opteeTaDevKit = prevJetpack.opteeTaDevKit.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ cfg.firmware.optee.patches;
        makeFlags = (old.makeFlags or [ ]) ++ cfg.firmware.optee.extraMakeFlags;
      });

      armTrustedFirmware = finalJetpack.callPackage ./pkgs/optee/arm-trusted-firmware.nix { };
      tosImage = finalJetpack.callPackage ./pkgs/optee/tos-image.nix { };

      flashInitrd =
        let
          modules = [ "qspi_mtd" "spi_tegra210_qspi" "at24" "spi_nor" ];
          modulesClosure = prev.makeModulesClosure {
            rootModules = modules;
            kernel = config.system.modulesTree;
            firmware = config.hardware.firmware;
            allowMissing = false;
          };
          jetpack-init = prev.writeScript "init" ''
            #!${prev.pkgsStatic.busybox}/bin/sh
            export PATH=${prev.pkgsStatic.busybox}/bin
            mkdir -p /proc /dev /sys
            mount -t proc proc -o nosuid,nodev,noexec /proc
            mount -t devtmpfs none -o nosuid /dev
            mount -t sysfs sysfs -o nosuid,nodev,noexec /sys

            for mod in ${builtins.toString modules}; do
              modprobe -v $mod
            done

            # `signedFirmware` must be built on x86_64, so we make a
            # concatenated initrd that places `signedFirmware` at a well
            # known path so that the final initrd can be constructed from
            # outside the context of this nixos config (which has an
            # aarch64-linux package-set).
            if ${lib.getExe finalJetpack.flashFromDevice} ${finalJetpack.signedFirmware}; then
              echo "Flashing platform firmware successful. Rebooting now."
              sync
              reboot -f
            else
              echo "Flashing platform firmware unsuccessful. Entering console"
              exec ${prev.pkgsStatic.busybox}/bin/sh
            fi
          '';
        in
        prev.makeInitrd {
          contents = [
            { object = jetpack-init; symlink = "/init"; }
            { object = "${modulesClosure}/lib"; symlink = "/lib"; }
          ];
        };

      # mkFlashScript is declared here due to its dependence on values from
      # `config`, but it is not inherently tied to any one particular
      # hostPlatform or buildPlatform (for example, it can be used to build
      # the "bup" entirely on an aarch64 build machine). mkFlashScript's
      # hostPlatform and buildPlatform is determined by which flash-tools
      # you give it, so if your flash-tools is for an x86_64-linux
      # hostPlatform, then mkFlashScript will generate script commands that
      # will need to be ran on x86_64-linux.
      mkFlashScript = flash-tools: args: import ./device-pkgs/flash-script.nix ({
        inherit lib flash-tools;
        inherit (cfg.firmware) eksFile;
        inherit (cfg.flashScriptOverrides) flashArgs partitionTemplate preFlashCommands postFlashCommands;
        inherit (finalJetpack) tosImage socType uefiFirmware;

        additionalDtbOverlays = args.additionalDtbOverlays or cfg.flashScriptOverrides.additionalDtbOverlays;
        dtbsDir = config.hardware.deviceTree.package;
      } // (builtins.removeAttrs args [ "additionalDtbOverlays" ]));

      bup = prev.runCommand "bup-${config.networking.hostName}-${finalJetpack.l4tVersion}"
        {
          inherit (cfg.firmware.secureBoot) requiredSystemFeatures;
        }
        ((finalJetpack.mkFlashScript
          final.pkgsBuildBuild.nvidia-jetpack.flash-tools # we need flash-tools for the buildPlatform
          {
            # TODO: Remove preSignCommands when we switch to using signedFirmware directly
            flashCommands = ''
              ${cfg.firmware.secureBoot.preSignCommands final.buildPackages}
            '' + lib.concatMapStringsSep "\n"
              (v: with v;
              "BOARDID=${boardid} BOARDSKU=${boardsku} FAB=${fab} BOARDREV=${boardrev} FUSELEVEL=${fuselevel} CHIPREV=${chiprev} ${lib.optionalString (chipsku != null) "CHIP_SKU=${chipsku}"} ${lib.optionalString (ramcode != null) "RAMCODE=${ramcode}"} ./flash.sh ${lib.optionalString (cfg.flashScriptOverrides.partitionTemplate != null) "-c flash.xml"} --no-flash --bup --multi-spec ${builtins.toString cfg.flashScriptOverrides.flashArgs}"
              )
              cfg.firmware.variants;
          }) + ''
          mkdir -p $out
          cp -r bootloader/payloads_*/* $out/
        '');

      # See l4t_generate_soc_bup.sh
      # python ${edk2-jetson}/BaseTools/BinWrappers/PosixLike/GenerateCapsule -v --encode --monotonic-count 1
      # NOTE: providing null public certs here will use the test certs in the EDK2 repo
      uefiCapsuleUpdate = prev.runCommand "uefi-${config.networking.hostName}-${finalJetpack.l4tVersion}.Cap"
        {
          nativeBuildInputs = [ prev.buildPackages.python3 prev.buildPackages.openssl ];
          inherit (cfg.firmware.uefi.capsuleAuthentication) requiredSystemFeatures;
        }
        (''
          ${cfg.firmware.uefi.capsuleAuthentication.preSignCommands final.buildPackages}
          bash ${final.pkgsBuildBuild.nvidia-jetpack.flash-tools}/generate_capsule/l4t_generate_soc_capsule.sh \
        '' + (lib.optionalString cfg.firmware.uefi.capsuleAuthentication.enable ''
          --trusted-public-cert ${cfg.firmware.uefi.capsuleAuthentication.trustedPublicCertPemFile} \
          --other-public-cert ${cfg.firmware.uefi.capsuleAuthentication.otherPublicCertPemFile} \
          --signer-private-cert ${cfg.firmware.uefi.capsuleAuthentication.signerPrivateCertPemFile} \
        '') + ''
          -i ${finalJetpack.bup}/bl_only_payload \
          -o $out \
          ${finalJetpack.socType}
        '');

      signedFirmware = final.runCommand "signed-${hostName}-${finalJetpack.l4tVersion}"
        { inherit (cfg.firmware.secureBoot) requiredSystemFeatures; }
        (finalJetpack.mkFlashScript final.pkgsBuildBuild.nvidia-jetpack.flash-tools {
          flashCommands = ''
            ${cfg.firmware.secureBoot.preSignCommands final}
          '' + lib.concatMapStringsSep "\n"
            (v: with v; ''
              BOARDID=${boardid} BOARDSKU=${boardsku} FAB=${fab} BOARDREV=${boardrev} FUSELEVEL=${fuselevel} CHIPREV=${chiprev} ${lib.optionalString (chipsku != null) "CHIP_SKU=${chipsku}"} ${lib.optionalString (ramcode != null) "RAMCODE=${ramcode}"} ./flash.sh ${lib.optionalString (cfg.flashScriptOverrides.partitionTemplate != null) "-c flash.xml"} --no-root-check --no-flash --sign ${builtins.toString cfg.flashScriptOverrides.flashArgs}

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

      flash-tools = prevJetpack.flash-tools.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ cfg.flashScriptOverrides.patches;
        postPatch = (old.postPatch or "") + cfg.flashScriptOverrides.postPatch;
      });

      # Use the flash-tools produced by mkFlashScript, we need whatever changes
      # the script made, as well as the flashcmd.txt from it
      flash-tools-flashcmd = finalJetpack.callPackage ./device-pkgs/flash-tools-flashcmd.nix {
        inherit cfg;
      };
    } // flashTools);
  }
)
