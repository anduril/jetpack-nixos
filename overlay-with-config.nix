# device-specific packages that are influenced by the nixos config
config:

let
  inherit (config.networking) hostName;
in

final: prev: (
  let
    cfg = config.hardware.nvidia-jetpack;

    inherit (final) lib;

    tosArgs = {
      inherit (final.nvidia-jetpack) socType;
      inherit (cfg.firmware.optee) taPublicKeyFile extraMakeFlags coreLogLevel taLogLevel;
      opteePatches = cfg.firmware.optee.patches;
    };

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

        # uefi-firmware can be evaluated only if som is set
        expectedBiosVersion = if (cfg.som != "generic") then finalJetpack.uefi-firmware.biosVersion else "Unknown";
      };

      uefi-firmware = prevJetpack.uefi-firmware.override ({
        bootLogo = cfg.firmware.uefi.logo;
        debugMode = cfg.firmware.uefi.debugMode;
        errorLevelInfo = cfg.firmware.uefi.errorLevelInfo;
        edk2NvidiaPatches = cfg.firmware.uefi.edk2NvidiaPatches;
        edk2UefiPatches = cfg.firmware.uefi.edk2UefiPatches;

        # A hash of something that represents everything that goes into the
        # platform firmware so that we can include it in the firmware version.
        # BUP should include everything relevant. However, bup also includes a
        # reference to uefi-firmware which would cause infinite recursion while
        # calculating the derivation hashes, so we need to "quotient out" the
        # uefi-firmware.  We do a fancy override scope here to make a version
        # of the bup that is otherwise identical, but does not depend on
        # uefi-firmware. The level of magic here can be frightening.
        uniqueHash =
          let
            cursedBup = (finalJetpack.overrideScope (a: b: {
              uefi-firmware = null;
            })).bup;
          in
          builtins.hashString "sha256" "${cursedBup}";
      } // lib.optionalAttrs cfg.firmware.uefi.capsuleAuthentication.enable {
        inherit (cfg.firmware.uefi.capsuleAuthentication) trustedPublicCertPemFile;
      });

      flash-tools = prevJetpack.flash-tools.overrideAttrs ({ patches ? [ ], postPatch ? "", ... }: {
        patches = patches ++ cfg.flashScriptOverrides.patches;
        postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
      });

      tosImage = finalJetpack.buildTOS tosArgs;
      taDevKit = finalJetpack.buildOpteeTaDevKit tosArgs;
      pkcs11Ta = finalJetpack.buildPkcs11Ta tosArgs;
      opteeXtest = finalJetpack.buildOpteeXtest tosArgs;
      inherit (finalJetpack.tosImage) nvLuksSrv hwKeyAgent;

      flashInitrd =
        let
          spiModules = if lib.versions.majorMinor config.system.build.kernel.version == "5.10" then [ "qspi_mtd" "spi_tegra210_qspi" "at24" "spi_nor" ] else [ "mtdblock" "spi_tegra210_quad" ];
          usbModules = if lib.versions.majorMinor config.system.build.kernel.version == "5.10" then [ ] else [ "libcomposite" "udc-core" "tegra-xudc" "xhci-tegra" "u_serial" "usb_f_acm" ];
          modules = spiModules ++ usbModules ++ cfg.flashScriptOverrides.additionalInitrdFlashModules;
          modulesClosure = prev.makeModulesClosure {
            rootModules = modules;
            kernel = config.system.modulesTree;
            firmware = config.hardware.firmware;
            allowMissing = false;
          };
          manufacturer = "NixOS";
          product = "serial";
          serialnumber = "0";
          jetpack-init = prev.writeScript "init" ''
            #!${prev.pkgsStatic.busybox}/bin/sh
            export PATH=${prev.pkgsStatic.busybox}/bin
            mkdir -p /proc /dev /sys
            mount -t proc proc -o nosuid,nodev,noexec /proc
            mount -t devtmpfs none -o nosuid /dev
            mount -t sysfs sysfs -o nosuid,nodev,noexec /sys
            ln -s /proc/self/fd /dev/ # for >(...) support

            for mod in ${builtins.toString modules}; do
              modprobe -v $mod
            done

            mount -t configfs none /sys/kernel/config
            if [ -e /sys/kernel/config/usb_gadget ] ; then
              # https://origin.kernel.org/doc/html/v5.10/usb/gadget_configfs.html
              gadget=/sys/kernel/config/usb_gadget/g.1
              mkdir $gadget

              echo 0x1d6b >$gadget/idVendor # Linux Foundation
              echo 0x104 >$gadget/idProduct # Multifunction Composite Gadget

              mkdir $gadget/strings/0x409
              echo ${manufacturer} >$gadget/strings/0x409/manufacturer
              echo ${product} >$gadget/strings/0x409/product
              echo ${serialnumber} >$gadget/strings/0x409/serialnumber

              mkdir $gadget/configs/c.1
              mkdir $gadget/functions/acm.usb0

              ln -s $gadget/functions/acm.usb0 $gadget/configs/c.1/

              echo "$(ls /sys/class/udc | head -n 1)" >$gadget/UDC

              # force into device mode if OTG and something is up with automatic detection
              if [ -w /sys/class/usb_role/usb2-0-role-switch/role ] ; then
                echo device > /sys/class/usb_role/usb2-0-role-switch/role
              fi

              sleep 5  # The configuration doesn't happen synchronously and takes >1 sec. 5 seconds seems like a good buffer and also gives time for host to connect
              mdev -s

              ttyGS=/dev/ttyGS$(cat $gadget/functions/acm.usb0/port_num)
              if [ -e $ttyGS ]; then
                exec &> >(tee $ttyGS) <$ttyGS
              fi
            fi

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
              echo "Flashing platform firmware unsuccessful."
              ${lib.optionalString (cfg.firmware.secureBoot.pkcFile == null) ''
              echo "Entering console"
              exec ${prev.pkgsStatic.busybox}/bin/sh
              ''}
            fi
          '';
        in
        (prev.makeInitrd {
          contents = [
            { object = jetpack-init; symlink = "/init"; }
            { object = "${modulesClosure}/lib"; symlink = "/lib"; }
          ];
        }).overrideAttrs (prev: {
          passthru = prev.passthru // {
            inherit manufacturer product serialnumber;
          };
        });

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
        inherit (finalJetpack) tosImage socType uefi-firmware;

        additionalDtbOverlays = args.additionalDtbOverlays or cfg.flashScriptOverrides.additionalDtbOverlays;
        dtbsDir = config.hardware.deviceTree.package;
      } // (builtins.removeAttrs args [ "additionalDtbOverlays" ]));

      bup = prev.runCommand "bup-${config.networking.hostName}-${finalJetpack.l4tMajorMinorPatchVersion}"
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
              (lib.concatStringsSep " " [
                "BOARDID=${boardid}"
                "BOARDSKU=${boardsku}"
                "FAB=${fab}"
                "BOARDREV=${boardrev}"
                "FUSELEVEL=${fuselevel}"
                "CHIPREV=${chiprev}"
                (lib.optionalString (chipsku != null) "CHIP_SKU=${chipsku}")
                (lib.optionalString (ramcode != null) "RAMCODE=${ramcode}")
                "./flash.sh"
                (lib.optionalString (cfg.flashScriptOverrides.partitionTemplate != null) "-c flash.xml")
                "--no-flash"
                (lib.optionalString (cfg.majorVersion == "6") "--sign")
                "--bup"
                "--multi-spec"
                (builtins.toString cfg.flashScriptOverrides.flashArgs)
              ]))
              cfg.firmware.variants;
          }) + ''
          mkdir -p $out
          cp -r bootloader/payloads_*/* $out/
        '');

      # See l4t_generate_soc_bup.sh
      # python ${edk2-jetson}/BaseTools/BinWrappers/PosixLike/GenerateCapsule -v --encode --monotonic-count 1
      # NOTE: providing null public certs here will use the test certs in the EDK2 repo
      uefiCapsuleUpdate = prev.runCommand "uefi-${config.networking.hostName}-${finalJetpack.l4tMajorMinorPatchVersion}.Cap"
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

      signedFirmware = final.runCommand "signed-${hostName}-${finalJetpack.l4tMajorMinorPatchVersion}"
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

      # Use the flash-tools produced by mkFlashScript, we need whatever changes
      # the script made, as well as the flashcmd.txt from it
      flash-tools-flashcmd = finalJetpack.callPackage ./device-pkgs/flash-tools-flashcmd.nix {
        inherit cfg;
      };
    } // flashTools);
  }
)
