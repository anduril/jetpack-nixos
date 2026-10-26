# device-specific packages that are influenced by the nixos config
config:

final: prev: (
  let
    cfg = config.hardware.nvidia-jetpack;

    inherit (final) lib;

    jetpackAtLeast = lib.versionAtLeast cfg.majorVersion;

    # L4T version packed the way flash.sh and l4t_generate_soc_capsule.sh encode it.
    fmpLowestSupportedVersion = lib.mapNullable
      (v: let p = map lib.toInt (lib.splitVersion v); in (builtins.elemAt p 0) * 65536 + (builtins.elemAt p 1) * 256 + (builtins.elemAt p 2))
      cfg.firmware.uefi.lowestSupportedVersion;

    flashTools = cfg.flasherPkgs.callPackages (import ./device-pkgs { inherit config; pkgs = final; }) { };
  in
  {
    nvidia-jetpack = prev.nvidia-jetpack.overrideScope (finalJetpack: prevJetpack: {
      socType =
        if cfg.som == null then null
        else if lib.hasPrefix "thor-" cfg.som then "t264"
        else if lib.hasPrefix "orin-" cfg.som then "t234"
        else if lib.hasPrefix "xavier-" cfg.som then "t194"
        else throw "Unknown SoC type";

      socFamily =
        if cfg.som == null then null
        else if lib.hasPrefix "thor-" cfg.som then "t26x"
        else if lib.hasPrefix "orin-" cfg.som then "t23x"
        else if lib.hasPrefix "xavier-" cfg.som then "t19x"
        else throw "Unknown SoC type";

      chipId =
        if cfg.som == null then null
        else if lib.hasPrefix "thor-" cfg.som then "0x26"
        else if lib.hasPrefix "orin-" cfg.som then "0x23"
        else if lib.hasPrefix "xavier-" cfg.som then "0x19"
        else throw "Unknown SoC type";

      pkcListChipId =
        if lib.hasPrefix "thor-" cfg.som then "0x260"
        else throw "Unknown SoC type";

      gpuDriver =
        if cfg.som == null then null
        else if lib.hasPrefix "thor-" cfg.som then "openrm"
        else if lib.hasPrefix "orin-" cfg.som then "nvgpu"
        else if lib.hasPrefix "xavier-" cfg.som then "nvgpu"
        else throw "Unknown SoC type";

      otaUtils = prevJetpack.otaUtils.override {
        inherit (config.boot.loader.efi) efiSysMountPoint;

        # uefi-firmware can be evaluated only if som is set
        expectedBiosVersion = if (cfg.som != "generic") then finalJetpack.uefi-firmware.biosVersion else "Unknown";
      };

      uefi-firmware = prevJetpack.uefi-firmware.override ({
        bootLogo = cfg.firmware.uefi.logo;
        inherit (cfg.firmware.uefi)
          debugMode
          errorLevelInfo
          printErrorLevel
          edk2NvidiaPatches
          edk2UefiPatches
          ;
        inherit (finalJetpack) socFamily;

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
      } // lib.optionalAttrs (prevJetpack.l4tAtLeast "36") {
        # r36+ only: r35's stuart argument set is closed, so it can't accept this.
        extraPackages = cfg.firmware.uefi.edk2ExtraPackages;
      } // lib.optionalAttrs (prevJetpack.l4tAtLeast "38") {
        # r38-only: when true, skip the disable-ftpm.diff patch so UEFI uses
        # the fTPM TA we embedded in tos.img. r35/r36 builders don't accept
        # this argument (their fn args don't include enableFTPM), so we only
        # pass it on r38+.
        enableFTPM = cfg.firmware.optee.ftpm.enable;
      } // lib.optionalAttrs cfg.firmware.uefi.capsuleAuthentication.enable {
        inherit (cfg.firmware.uefi.capsuleAuthentication) trustedPublicCertPemFile;
      });

      jetsonStandaloneMMOptee = prevJetpack.jetsonStandaloneMMOptee.override
        {
          inherit (cfg.firmware.uefi)
            debugMode
            errorLevelInfo
            printErrorLevel
            edk2NvidiaPatches
            edk2UefiPatches
            ;
          inherit (finalJetpack) socFamily;
        } // lib.optionalAttrs (prevJetpack.l4tAtLeast "36") {
        extraPackages = cfg.firmware.uefi.standaloneMMExtraPackages;
      };

      flash-tools = prevJetpack.flash-tools.overrideAttrs ({ patches ? [ ], postPatch ? "", ... }: {
        patches = patches ++ cfg.flashScriptOverrides.patches;
        postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
      });

      armTrustedFirmware = prevJetpack.armTrustedFirmware.overrideAttrs {
        inherit (finalJetpack) socType;
      };

      msTpm20RefTa = prevJetpack.msTpm20RefTa.overrideAttrs (prevAttrs: {
        patches = prevAttrs.patches or [ ] ++ cfg.firmware.optee.patches;
        makeFlags = prevAttrs.makeFlags or [ ]
          ++ [ "CFG_TEE_TA_LOG_LEVEL=${toString cfg.firmware.optee.ftpm.taLogLevel}" ]
          ++ lib.optional cfg.firmware.optee.ftpm.measuredBoot "CFG_TA_MEASURED_BOOT=y";
      });

      # General OP-TEE build config; TA derivations stay on optee-os to
      # avoid an optee-config -> fTPM TA -> taDevKit -> optee-config cycle.
      optee-config = prevJetpack.optee-config.overrideAttrs (prevAttrs: {
        inherit (finalJetpack) socType;
        inherit (cfg.firmware.optee) taPublicKeyFile coreLogLevel taLogLevel;
        patches = prevAttrs.patches or [ ] ++ cfg.firmware.optee.patches;
        makeFlags = prevAttrs.makeFlags or [ ] ++ cfg.firmware.optee.extraMakeFlags;
        enableFTPM = cfg.firmware.optee.ftpm.enable;
        measuredBoot = cfg.firmware.optee.ftpm.measuredBoot;
        unsecureInjectEPS = cfg.firmware.optee.ftpm.unsecureInjectEPS.enable;
      });

      optee-os = prevJetpack.optee-os.overrideAttrs (_: {
        ftpmHelperTa =
          if cfg.firmware.optee.ftpm.enable
          then finalJetpack.ftpmHelperTa else null;
        msTpm20RefTa =
          if cfg.firmware.optee.ftpm.enable
          then finalJetpack.msTpm20RefTa else null;
      });
      opteeClient = prevJetpack.opteeClient.overrideAttrs (prevAttrs: {
        patches = prevAttrs.patches or [ ] ++ cfg.firmware.optee.patches;
        makeFlags = prevAttrs.makeFlags or [ ] ++ cfg.firmware.optee.extraMakeFlags;
      });

      flashInitrd = final.callPackage ./device-pkgs/flash-initrd {
        extraModules = cfg.flashScriptOverrides.additionalInitrdFlashModules;
        inherit (finalJetpack) flashFromDevice signedFirmware;
        extraConfig = {
          boot = {
            inherit (config.boot) kernelPackages extraModulePackages;
            initrd.systemd.emergencyAccess = cfg.firmware.secureBoot.pkcFile == null;
          };
        };
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
        inherit fmpLowestSupportedVersion;
        inherit (cfg.flashScriptOverrides) flashArgs partitionTemplate preFlashCommands postFlashCommands;
        inherit (finalJetpack) tosImage socType socFamily uefi-firmware l4tAtLeast;

        additionalDtbOverlays = args.additionalDtbOverlays or cfg.flashScriptOverrides.additionalDtbOverlays;
        dtbsDir = config.hardware.deviceTree.package;
      } // (builtins.removeAttrs args [ "additionalDtbOverlays" ]));

      bup = prev.runCommand "bup-${cfg.name}-${finalJetpack.l4tMajorMinorPatchVersion}"
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
                (lib.optionalString (jetpackAtLeast "6") "--sign")
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
      uefiCapsuleUpdate = prev.runCommand "uefi-${cfg.name}-${finalJetpack.l4tMajorMinorPatchVersion}.Cap"
        {
          nativeBuildInputs = [ prev.buildPackages.python3 prev.buildPackages.openssl ];
          inherit (cfg.firmware.uefi.capsuleAuthentication) requiredSystemFeatures;
        }
        (''
          ${cfg.firmware.uefi.capsuleAuthentication.preSignCommands final.buildPackages}
          ${lib.optionalString (fmpLowestSupportedVersion != null) "export FMP_LOWEST_SUPPORTED_VERSION=${toString fmpLowestSupportedVersion}"}
          bash ${final.pkgsBuildBuild.nvidia-jetpack.flash-tools}/generate_capsule/l4t_generate_soc_capsule.sh \
        '' + (lib.optionalString cfg.firmware.uefi.capsuleAuthentication.enable ''
          --trusted-public-cert ${lib.escapeShellArg "${cfg.firmware.uefi.capsuleAuthentication.trustedPublicCertPemFile}"} \
          --other-public-cert ${lib.escapeShellArg "${cfg.firmware.uefi.capsuleAuthentication.otherPublicCertPemFile}"} \
          --signer-private-cert ${lib.escapeShellArg "${cfg.firmware.uefi.capsuleAuthentication.signerPrivateCertPemFile}"} \
        '') + ''
          -i ${finalJetpack.bup}/bl_only_payload \
          -o $out \
          ${finalJetpack.socType}
        '');

      signedFirmware =
        let
          signedDir = if cfg.firmware.secureBoot.sbkFile != null then "enc_signed" else "signed";
        in
        final.runCommand "signed-${cfg.name}-${finalJetpack.l4tMajorMinorPatchVersion}"
          { inherit (cfg.firmware.secureBoot) requiredSystemFeatures; }
          (finalJetpack.mkFlashScript final.pkgsBuildBuild.nvidia-jetpack.flash-tools {
            flashCommands = ''
              ${cfg.firmware.secureBoot.preSignCommands final}
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
                "--no-root-check"
                "--no-flash"
                "--sign"
                "${builtins.toString cfg.flashScriptOverrides.flashArgs}"
              ]) + "\n" +
              ''
                outdir=$out/${boardid}-${fab}-${boardsku}-${boardrev}-${if fuselevel == "fuselevel_production" then "1" else "0"}-${chiprev}--
                mkdir -p $outdir

                cp -v bootloader/${signedDir}/flash.idx $outdir/

                # Copy files referenced by flash.idx
                while IFS=", " read -r partnumber partloc start_location partsize partfile partattrs partsha; do
                  if [[ "$partfile" != "" ]]; then
                    if [[ -f "bootloader/${signedDir}/$partfile" ]]; then
                      cp -v "bootloader/${signedDir}/$partfile" $outdir/
                    elif [[ -f "bootloader/$partfile" ]]; then
                      cp -v "bootloader/$partfile" $outdir/
                    else
                      echo "Unable to find $partfile"
                      exit 1
                    fi
                  fi
                done < bootloader/${signedDir}/flash.idx

                rm -rf bootloader/${signedDir}
              '')
              cfg.firmware.variants;
          });

      # Use the flash-tools produced by mkFlashScript, we need whatever changes
      # the script made, as well as the flashcmd.txt from it
      flash-tools-flashcmd = finalJetpack.callPackage ./device-pkgs/flash-tools-flashcmd.nix {
        inherit cfg;
      };

      # Generates `pkgs.nvidia-jetpack.pkcList` which contains the required PKC list xml files.
      #
      # XXX Note that the private key pems are copied to the nix store! You will need to write your
      # own helper function if you want to use sandbox exception paths for the keys!
      #
      # Note that the "signed" and "reference" copies of the PKC keylist are created in this
      # package because `tegrasign_v3_internal.py` wants to make copies of the keylist file but the
      # keylist file lives in the read only nix store. The bsp patch ensures that the build will
      # fail if there is an unexpected diff between the copy and the expected.
      mkPkcList =
        {
          # Directory containing per-slot private-key PEMs. Filenames must follow the convention
          # `<keyType>_<keyNum>.pem` per the Jetson developer guide examples.
          privateKeyDir
        , # PKC slot index [0..15] used to sign BCT and boot images.
          activeKeyIndex
        , # Number of keys to include in the PKC keylist, from 1..N. Only the included keys are
          # used to produce the `pkcListComboHash` package which contains the fuse value.
          numKeys
        , # Key type identifier from the Jetson developer guide. Examples include `rsa3k` for
          # RSA-3072, `ecp256` / `ecp521` for ECDSA, `ed25519`, `xmss`.
          keyType
        ,
        }:
        prev.runCommand "pkc-list-${cfg.name}" { } (
          lib.concatStringsSep "\n" [
            ''
              mkdir -p $out
            ''
            (lib.concatStringsSep "\n" (
              lib.forEach (lib.range 0 (numKeys - 1)) (keyId: ''
                cp "${privateKeyDir}/${keyType}_${toString keyId}.pem" $out/
              '')
            ))
            ''
              cat > $out/pkc_keylist.xml <<EOF
              <?xml version="1.0"?>
              <entry_list>
                <bct
                  active_index="${toString activeKeyIndex}"
                  chip_id="${finalJetpack.pkcListChipId}"
                  pcp_file="active_key.pcp"
                  pcps_file="active_key.pcps"
                  pcps_hash_file="active_key.pcps.hash"
                />
            ''
            (lib.concatStringsSep "\n" (lib.forEach (lib.range 0 (numKeys - 1)) (keyId: ''
              <entry
                key_id="${toString keyId}"
                mode="pkc"
                key="${placeholder "out"}/${keyType}_${toString keyId}.pem"
                pub_file="${keyType}_${toString keyId}.pub"
                hash_file="${keyType}_${toString keyId}.pub.hash"
              />
            '')))
            ''
              </entry_list>
              EOF

              cp $out/pkc_keylist.xml $out/pkc_keylist_signed.xml
              cp $out/pkc_keylist.xml $out/pkc_keylist_signed_ref.xml
            ''
          ]
        );
    } // flashTools);
  }
)
