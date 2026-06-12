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
, writeText
, deviceTree
, tio
, expect
, coreutils
, e2fsprogs
, gawk
, mtools
, zstd
}:

let
  cfg = config.hardware.nvidia-jetpack;

  # We need to grab some packages from the device's aarch64 package set.
  inherit (pkgs.nvidia-jetpack)
    chipId
    flashInitrd
    mkFlashScript
    l4tMajorMinorPatchVersion
    l4tAtLeast
    ;

  jetpackAtLeast = lib.versionAtLeast cfg.majorVersion;
  jetpackOlder = lib.versionOlder cfg.majorVersion;

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

  # Inside a Nix derivation (sandboxed), call the flash.sh scripts and others
  # to produce a flashcmd.txt that will be run directly. This removes most of
  # the dynamism available to the flash script and requires specifying many
  # more environment variables which are normally autodetected
  useFlashCmd = builtins.length cfg.firmware.variants == 1;

  # With either produce a standard flash script, which does variant detection,
  # or if there is only a single variant, will produce a script specialized to
  # that particular variant.
  mkFlashScriptAuto = if useFlashCmd then mkFlashCmdScript else (mkFlashScript nvidia-jetpack.flash-tools);

  # Generate a flash script using the built configuration options set in a NixOS configuration
  legacyFlashScript = writeShellApplication {
    name = "flash-${cfg.name}";
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
      '' + lib.optionalString (cfg.firmware.secureBoot.pkcFile != null) ''
        # If secure boot is enabled, nvidia requires the kernel to be signed
        (
          ${cfg.firmware.secureBoot.preSignCommands buildPackages}
          # See l4t_uefi_sign_image.sh from BSP, or tools/README_uefi_secureboot.txt
          # This is not good
          bash ./l4t_uefi_sign_image.sh --image ./kernel/Image --cert ${cfg.firmware.uefi.secureBoot.signer.cert} --key ${cfg.firmware.uefi.secureBoot.signer.key} --mode nosplit
        )
      '';

      flashArgs =
        [ "--rcm-boot" ]
        # JetPack 7 wants to rebuild system.img with rootfs by default, we don't want that
        ++ lib.optional (jetpackAtLeast "7") "-r"
        # A little jank, but don't have the flash script itself actually flash, just produce the flashcmd.txt file
        # We need to sign the boot.img file afterwards in this script
        ++ lib.optional (cfg.firmware.secureBoot.pkcFile != null) "--no-flash"
        ++ cfg.flashScriptOverrides.flashArgs;

      postFlashCommands = lib.optionalString (cfg.firmware.secureBoot.pkcFile != null) ''
        (
          # If secure boot is enabled, the boot.img needs to be signed.
          cd bootloader
          ${cfg.firmware.secureBoot.preSignCommands buildPackages}
          # See l4t_uefi_sign_image.sh from BSP, or tools/README_uefi_secureboot.txt
          bash ../l4t_uefi_sign_image.sh --image boot.img --cert ${cfg.firmware.uefi.secureBoot.signer.cert} --key ${cfg.firmware.uefi.secureBoot.signer.key} --mode append
        )
      '' + lib.optionalString (!useFlashCmd && cfg.firmware.secureBoot.pkcFile != null) ''
        (
          # Now execute flash
          echo "Flashing device now"
          cd bootloader; bash ./flashcmd.txt
        )
      '';
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
      name = "initrd-flash-${cfg.name}";
      text = import ./initrdflash-script.nix { inherit mkRcmBootScript config flashInitrd lib l4tMajorMinorPatchVersion writeText deviceTree tio expect; };
      meta.platforms = [ "x86_64-linux" ];
    };

  extractSignedOrinArtifacts = writeShellApplication {
    name = "extract-signed-orin-artifacts";
    runtimeInputs = [
      coreutils
      e2fsprogs
      gawk
      mtools
      zstd
    ];
    text = builtins.readFile ./extract-signed-orin-artifacts.sh;
    meta = {
      description = "Helper that extracts signed Jetson Orin artifacts from an sd-image build result";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  };

  flashScript = writeShellApplication {
    name = "flash-${cfg.name}";
    runtimeInputs = [
      coreutils
      extractSignedOrinArtifacts
    ];
    text = ''
      set -euo pipefail

      usage() {
        cat <<'USAGE'
      Usage: flash-${cfg.name} [options] [-s <signed-sd-image>]

        -s, --signed-sd-image DIR   Path to signed sd-image result directory.
                                    When provided, signed boot artifacts are automatically
                                    extracted before flashing.
        -h, --help                  Show this help and exit.

      All other arguments are forwarded to NVIDIA's flashing script verbatim.
      USAGE
      }

      signed_sd_image=""

      while [[ $# -gt 0 ]]; do
        case "$1" in
          -s|--signed-sd-image)
            if [[ $# -lt 2 ]]; then
              echo "Missing argument for $1" >&2
              usage
              exit 1
            fi
            signed_sd_image="$2"
            if ! signed_sd_image=$(realpath -e "$signed_sd_image"); then
              echo "Signed image directory not found: $2" >&2
              exit 1
            fi
            shift 2
            ;;
          -h|--help)
            usage
            exit 0
            ;;
          --)
            shift
            break
            ;;
          *)
            break
            ;;
        esac
      done

      temp_signed_dir=""
      cleanup() {
        if [[ -n "$temp_signed_dir" && -d "$temp_signed_dir" ]]; then
          rm -rf "$temp_signed_dir"
        fi
      }

      unset SIGNED_ARTIFACTS_DIR
      unset SIGNED_SD_IMAGE_DIR

      if [[ -n "$signed_sd_image" ]]; then
        if [[ ! -d "$signed_sd_image" ]]; then
          echo "Signed image directory not found: $signed_sd_image" >&2
          exit 1
        fi

        temp_signed_dir=$(mktemp -d)
        trap cleanup EXIT

        ${extractSignedOrinArtifacts}/bin/extract-signed-orin-artifacts \
          --sd-image-dir "$signed_sd_image" \
          --output "$temp_signed_dir" \
          --force >/dev/null

        export SIGNED_ARTIFACTS_DIR="$temp_signed_dir"
        export SIGNED_SD_IMAGE_DIR="$signed_sd_image"
      fi

      "${legacyFlashScript}/bin/flash-${cfg.name}" "$@"
      status=$?
      cleanup
      exit $status
    '';
    meta.platforms = [ "x86_64-linux" ];
  };

  fuseScript = writeShellApplication {
    name = "fuse-${cfg.name}";
    text = import ./flash-script.nix {
      inherit lib l4tAtLeast;
      inherit (nvidia-jetpack) flash-tools socFamily;
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
{ inherit initrdFlashScript legacyFlashScript fuseScript rcmBoot flashScript; }
