# The firmware and flashing package set configured for one NixOS configuration:
# UEFI, OP-TEE, trusted firmware, BUP and capsules, and the flashing/fusing
# tools. It depends on `config`, so it is
# `config.hardware.nvidia-jetpack.firmwarePkgs` rather than part of `pkgs`. That
# way `pkgs` stays independent of any one machine and can be shared between
# configurations.
#
# `pkgs` is the platform this instance is built for: the device's own package
# set, the flashing host's (`hardware.nvidia-jetpack.flasherPkgs`), or the build
# platform's when cross-compiling. `extensions`
# (`hardware.nvidia-jetpack.firmwarePkgsExtensions`) are applied to every
# instance.
#
# Returns two forms of the same packages: `scope`, a standalone package set
# (`config.hardware.nvidia-jetpack.firmwarePkgs` when `pkgs` is read-only), and
# `extension`, an overlay-style extension of `pkgs.nvidia-jetpack` (when the module
# instantiates Nixpkgs itself, `firmwarePkgs` is `pkgs.nvidia-jetpack`).
{ config
, pkgs
, # The device package set is distinct from pkgs in flashing/build scopes.
  devicePkgs ? pkgs
, extensions ? [ ]
,
}:

let
  inherit (pkgs) lib;
  sdk = pkgs.nvidia-jetpack;

  cfg = config.hardware.nvidia-jetpack;

  soc = import ./soc.nix { inherit lib; };
  socType = soc.socTypeForSom cfg.som;
  socInfo =
    if socType != null then
      soc.socs.${socType}
    else
      throw "hardware.nvidia-jetpack.som must name a specific SoM, not \"${cfg.som}\", to build firmware";

  jetpackAtLeast = lib.versionAtLeast cfg.majorVersion;

  # Another instance of this package set, with the same configuration and extensions.
  forPkgs =
    otherPkgs:
    (import ./firmware-packages.nix {
      inherit config devicePkgs extensions;
      pkgs = otherPkgs;
    }).scope;

  # L4T version packed the way flash.sh and l4t_generate_soc_capsule.sh encode it.
  fmpLowestSupportedVersion = lib.mapNullable
    (v: let p = map lib.toInt (lib.splitVersion v); in (builtins.elemAt p 0) * 65536 + (builtins.elemAt p 1) * 256 + (builtins.elemAt p 2))
    cfg.firmware.uefi.lowestSupportedVersion;

  # Picks the package set that runs NVIDIA's L4T tools. Unset, it returns the
  # caller's own set, which keeps the derivations (and the UEFI version stamp
  # derived from them) unchanged.
  flasherPkgsOr = pkgs: if cfg.firmware.useFlasherPkgsForL4tTools then cfg.flasherPkgs else pkgs;

  # The flashing/fusing tools run on the flashing host, so they are built from
  # its instance of this package set.
  flashTools =
    cfg.flasherPkgs.callPackages
      (import ./device-pkgs {
        inherit config pkgs;
      })
      {
        nvidia-jetpack = cfg.flasherFirmwarePkgs;
      };

  # Defined both here and in `pkgs.nvidia-jetpack` on purpose: the unconfigured
  # tools, of which this package set builds its own configured copies, and the SoC
  # that `lib.nixpkgsArgsFor` selects. Anything else this package set defines is
  # firmware that is configured per machine.
  sdkOverlap = [ "flash-tools" "otaUtils" "ftpmManufacturingTools" "socType" "chipId" ];

  applyExtensions = scope: if extensions == [ ] then scope else scope.overrideScope (lib.composeManyExtensions extensions);

  mkExtension = buildPlatformJetpack: finalJetpack: _:
    let
      l4tMajorVersion = lib.versions.major finalJetpack.l4tMajorMinorPatchVersion;
      opteeArgs = {
        optee-config = {
          inherit (cfg.firmware.optee) taPublicKeyFile coreLogLevel taLogLevel patches extraMakeFlags;
          enableFTPM = cfg.firmware.optee.ftpm.enable;
          measuredBoot = cfg.firmware.optee.ftpm.measuredBoot;
          unsecureInjectEPS = cfg.firmware.optee.ftpm.unsecureInjectEPS.enable;
        };
        optee-os = {
          ftpmHelperTa = if cfg.firmware.optee.ftpm.enable then finalJetpack.ftpmHelperTa else null;
          msTpm20RefTa = if cfg.firmware.optee.ftpm.enable then finalJetpack.msTpm20RefTa else null;
        };
        msTpm20RefTa = {
          inherit (cfg.firmware.optee) patches;
          inherit (cfg.firmware.optee.ftpm) taLogLevel measuredBoot;
        };
        opteeClient = {
          inherit (cfg.firmware.optee) patches extraMakeFlags;
        };
      };
      # Every recipe in ./pkgs/optee is built here: they depend on this machine's
      # OP-TEE configuration, directly or through the TA dev kit.
      opteePkgs = lib.packagesFromDirectoryRecursive {
        callPackage = path: args:
          finalJetpack.callPackage path (args // (opteeArgs.${lib.removeSuffix ".nix" (baseNameOf path)} or { }));
        directory = ./pkgs/optee;
      };
      nativeBuild = pkgs.stdenv.buildPlatform.config == pkgs.stdenv.hostPlatform.config;
      buildFirmwarePkgs = if nativeBuild then finalJetpack else buildPlatformJetpack;
      buildPlatformFlashTools = buildFirmwarePkgs.flash-tools;
      l4tFlashTools = if cfg.firmware.useFlasherPkgsForL4tTools then cfg.flasherFirmwarePkgs.flash-tools else buildPlatformFlashTools;
    in
    opteePkgs
    // {
      inherit socType;
      socFamily = socInfo.family;
      chipId = socInfo.chipId;
      pkcListChipId = if socInfo.pkcListChipId != null then socInfo.pkcListChipId else throw "Unknown SoC type";

      # Built here from the recipe, like the firmware, rather than by overriding
      # the unconfigured `pkgs.nvidia-jetpack.otaUtils`.
      otaUtils = finalJetpack.callPackage ./pkgs/ota-utils {
        inherit (config.boot.loader.efi) efiSysMountPoint;

        # uefi-firmware can be evaluated only if som is set
        expectedBiosVersion = if (cfg.som != "generic") then finalJetpack.uefi-firmware.biosVersion else "Unknown";
      };

      inherit (finalJetpack.callPackages ./pkgs/uefi-firmware/r${l4tMajorVersion} ({
        inherit (finalJetpack) l4tMajorMinorPatchVersion socFamily;
        patchfv = buildFirmwarePkgs.patchfv;
        bootLogo = cfg.firmware.uefi.logo;
        inherit (cfg.firmware.uefi)
          debugMode
          errorLevelInfo
          printErrorLevel
          edk2NvidiaPatches
          edk2UefiPatches
          ;

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
      } // lib.optionalAttrs (finalJetpack.l4tAtLeast "36") {
        # r36+ only: r35's stuart argument set is closed, so it can't accept this.
        extraPackages = cfg.firmware.uefi.edk2ExtraPackages;
      } // lib.optionalAttrs (finalJetpack.l4tAtLeast "38") {
        # r38-only: when true, skip the disable-ftpm.diff patch so UEFI uses
        # the fTPM TA we embedded in tos.img. r35/r36 builders don't accept
        # this argument (their fn args don't include enableFTPM), so we only
        # pass it on r38+.
        enableFTPM = cfg.firmware.optee.ftpm.enable;
      } // lib.optionalAttrs cfg.firmware.uefi.capsuleAuthentication.enable {
        inherit (cfg.firmware.uefi.capsuleAuthentication) trustedPublicCertPemFile;
      })) uefi-firmware;

      inherit (finalJetpack.callPackages ./pkgs/uefi-firmware/r${l4tMajorVersion} ({
        inherit (finalJetpack) l4tMajorMinorPatchVersion socFamily;
        patchfv = buildFirmwarePkgs.patchfv;
        inherit (cfg.firmware.uefi)
          debugMode
          errorLevelInfo
          printErrorLevel
          edk2NvidiaPatches
          edk2UefiPatches
          ;
      } // lib.optionalAttrs (finalJetpack.l4tAtLeast "36") {
        extraPackages = cfg.firmware.uefi.standaloneMMExtraPackages;
      })) jetsonStandaloneMMOptee;

      # Built here from the recipe, so firmware extensions to its inputs
      # (`bspSrc`, ...) flow in. Customize it with `firmwarePkgsExtensions`;
      # overrides of the unconfigured `pkgs.nvidia-jetpack.flash-tools` do not
      # reach it.
      flash-tools = (finalJetpack.callPackage ./pkgs/flash-tools { }).overrideAttrs ({ patches ? [ ], postPatch ? "", ... }: {
        patches = patches ++ cfg.flashScriptOverrides.patches;
        postPatch = postPatch + cfg.flashScriptOverrides.postPatch;
      });

      # This environment RUNS on the device, even when this firmware scope is
      # for x86 flashing/build tools. Reuse the outer NixOS package set exactly;
      # never auto-fill pkgs or runtime helpers from the flashing host's scope.
      flashInitrd = devicePkgs.callPackage ./device-pkgs/flash-initrd {
        pkgs = devicePkgs;
        extraModules = cfg.flashScriptOverrides.additionalInitrdFlashModules;
        inherit (cfg.firmwarePkgs) flashFromDevice signedFirmware;
        extraConfig = {
          imports = [ cfg.flashScriptOverrides.additionalInitrdFlashNixosModules ];
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

      bup = (flasherPkgsOr pkgs).runCommand "bup-${cfg.name}-${finalJetpack.l4tMajorMinorPatchVersion}"
        {
          inherit (cfg.firmware.secureBoot) requiredSystemFeatures;
        }
        ((finalJetpack.mkFlashScript
          l4tFlashTools # we need flash-tools for the platform that runs them
          {
            # TODO: Remove preSignCommands when we switch to using signedFirmware directly
            flashCommands = ''
              ${cfg.firmware.secureBoot.preSignCommands (flasherPkgsOr pkgs.buildPackages)}
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
      uefiCapsuleUpdate = pkgs.runCommand "uefi-${cfg.name}-${finalJetpack.l4tMajorMinorPatchVersion}.Cap"
        {
          nativeBuildInputs = [ pkgs.buildPackages.python3 pkgs.buildPackages.openssl ];
          inherit (cfg.firmware.uefi.capsuleAuthentication) requiredSystemFeatures;
        }
        (''
          ${cfg.firmware.uefi.capsuleAuthentication.preSignCommands pkgs.buildPackages}
          ${lib.optionalString (fmpLowestSupportedVersion != null) "export FMP_LOWEST_SUPPORTED_VERSION=${toString fmpLowestSupportedVersion}"}
          bash ${buildPlatformFlashTools}/generate_capsule/l4t_generate_soc_capsule.sh \
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
          signedDir =
            if cfg.firmware.secureBoot.sbkFile == null then "signed"
            else if finalJetpack.socFamily == "t19x" then "encrypted_signed_t19x"
            else "enc_signed";
        in
        (flasherPkgsOr pkgs).runCommand "signed-${cfg.name}-${finalJetpack.l4tMajorMinorPatchVersion}"
          { inherit (cfg.firmware.secureBoot) requiredSystemFeatures; }
          (finalJetpack.mkFlashScript l4tFlashTools {
            flashCommands = ''
              ${cfg.firmware.secureBoot.preSignCommands (flasherPkgsOr pkgs)}
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
        # This runs on the flashing host, but embeds the device's ARM
        # firmware. Do not auto-fill mkFlashScript from an x86 firmware
        # scope (which would try to build OP-TEE/UEFI for x86).
        mkFlashScript = cfg.firmwarePkgs.mkFlashScript;
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
        pkgs.runCommand "pkc-list-${cfg.name}" { } (
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
    } // flashTools;
in
{
  extension = lib.composeManyExtensions ([ (mkExtension pkgs.pkgsBuildBuild.nvidia-jetpack) ] ++ extensions);

  scope =
    let
      # Fail on overlays that still put firmware into `pkgs.nvidia-jetpack`. This
      # package set would otherwise silently shadow them. Only names are forced.
      shadowedAttrs = builtins.filter
        (name: sdk ? ${name} && !(lib.elem name sdkOverlap))
        (builtins.attrNames (mkExtension null sdk sdk));
    in
    assert lib.assertMsg (shadowedAttrs == [ ]) ''
      pkgs.nvidia-jetpack defines ${lib.concatStringsSep ", " shadowedAttrs}. Firmware is configured per machine,
      in config.hardware.nvidia-jetpack.firmwarePkgs, so these would be ignored. Move the override from the
      overlays that `pkgs` was instantiated with to hardware.nvidia-jetpack.firmwarePkgsExtensions.
    '';
    applyExtensions (lib.makeScope sdk.newScope (finalJetpack:
      {
        # Only these SDK inputs/helpers are part of the firmware API. sdk.newScope
        # supplies Nixpkgs + SDK automatic arguments without exporting userspace.
        # Rebind callPackages as well: its nested callPackage (e.g. Stuart) must see
        # this firmware fixed point, not the SDK's or top-level Nixpkgs'.
        inherit (sdk) bspSrc gitRepos l4tMajorMinorPatchVersion jetpackMajorMinorPatchVersion
          l4tAtLeast l4tOlder patchfv flashFromDevice;
        callPackages = lib.callPackagesWith (pkgs // sdk // finalJetpack);
      }
      // mkExtension (forPkgs pkgs.pkgsBuildBuild) finalJetpack sdk));
}
