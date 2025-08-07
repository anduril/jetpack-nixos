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
, picocom
}:

let
  cfg = config.hardware.nvidia-jetpack;
  inherit (config.networking) hostName;

  # We need to grab some packages from the device's aarch64 package set.
  inherit (pkgs.nvidia-jetpack)
    chipId
    flashInitrd
    mkFlashScript
    l4tMajorMinorPatchVersion
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
  flashScript = writeShellApplication {
    name = "flash-${hostName}";
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
      name = "initrd-flash-${hostName}";
      runtimeInputs = [ picocom ];
      text =
        let
          inherit (flashInitrd.passthru) manufacturer product serialnumber;
          serialPortId = "usb-${manufacturer}_${product}_${serialnumber}-if00";
        in
        ''
          ${mkRcmBootScript {
            kernelPath = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
            initrdPath = "${flashInitrd}/initrd";
            kernelCmdline = lib.concatStringsSep " " [
              "console=ttyTCU0,115200" "sdhci_tegra.en_boot_part_access=1"
            ];
            # During the initrd flash script, we upload two edk2 builds to the
            # board, one that is only used temporarily to boot into our
            # kernel/initrd to perform the flashing, and another one that is
            # persisted to the firmware storage medium for future booting. We
            # don't want to influence the boot order of the temporary edk2 since
            # this may cause that edk2 to boot from something other than our
            # intended flashing kernel/initrd combo (e.g. disk or network). Since
            # the edk2 build that we actually persist to the board is embedded in
            # the initrd used for flashing, we have the desired boot order (as
            # configured in nix) in there and is not affected dynamically during
            # the flashing procedure. NVIDIA ensures that when the device is
            # using RCM boot, only the boot mode named "boot.img" is used (see https://gist.github.com/jmbaur/1ca79436e69eadc0a38ec0b43b16cb2f#file-flash-sh-L1675).
            additionalDtbOverlays = (lib.filter (path: (path.name or "") != "DefaultBootOrder.dtbo") cfg.flashScriptOverrides.additionalDtbOverlays) ++ [(pkgs.deviceTree.compileDTS {
              # We force USB port to peripheral mode, in case the carrier board doesn't support OTG
              # Fortunately, the USB controller is all in the SoC, so we can override it directly here
              name = "force-xusb-peripheral.dtbo";
              dtsFile = let
                overridePaths = {
                  "36" = {
                    orin = {
                      xudcPadctlPath = "bus@0/padctl@3520000";
                      xudcPath = "bus@0/usb@3550000";
                    };
                  };
                  "35" = {
                    orin = {
                      xudcPadctlPath = "xusb_padctl@3520000";
                      xudcPath = "xudc@3550000";
                    };
                    xavier = {
                      xudcPadctlPath = "xusb_padctl@3520000";
                      xudcPath = "xudc@3550000";
                    };
                  };
                };
                l4tMajor = lib.versions.major l4tMajorMinorPatchVersion;
                soc = builtins.elemAt (lib.strings.split "-" cfg.som) 0;
                inherit (overridePaths.${l4tMajor}.${soc}) xudcPadctlPath xudcPath;
              in pkgs.writeText "dts" ''
                /dts-v1/;

                / {
                  fragment@0 {
                    target-path = "/${xudcPadctlPath}/ports/usb2-0";

                    board_config {
                      sw-modules = "kernel", "uefi";
                    };

                    __overlay__ {
                      mode = "peripheral";
                      /* usb-role-switch and connector are required
                       * use a dummy connector that claims USB is connected at boot
                       */
                      usb-role-switch;
                      connector {
                        compatible = "usb-b-connector", "gpio-usb-b-connector";
                        label = "usb-recovery";
                        cable-connected-on-boot = <2>;
                      };
                    };
                  };

                  fragment@1 {
                    target-path = "/${xudcPath}";

                    board_config {
                      sw-modules = "kernel", "uefi";
                    };

                    __overlay__ {
                      status = "okay";
                    };
                  };
                };
              '';
            })];
          }}
          echo
          echo "Jetson device should now be flashing and will reboot when complete."

          # TODO(eberman): maybe stop assuming /dev/serial/by-id is present
          # It'll be populated with udev, so most Linux systems will work fine
          echo -n "Waiting for Jetson device to appear via USB, this may take up to 4 minutes"

          counter=0
          until [[ -e /dev/serial/by-id/${serialPortId} || $counter -gt ${builtins.toString (4 * 60 * 2)} ]] ; do
            echo -n "."
            sleep 0.5
            ((++counter))
          done
          echo

          if [ ! -e /dev/serial/by-id/${serialPortId} ] ; then
            echo "Jetson device not detected, please monitor the serial port or wait 5-15 minutes"
            exit 2
          fi

          logs=$(mktemp)
          echo "^a^x to kill the terminal"
          picocom --quiet --logfile "$logs" /dev/serial/by-id/${serialPortId} || true

          if ! grep -q "Flashing platform firmware successful" "$logs" ; then
            rm "$logs"
            echo "Flashing may have failed"
            exit 1
          fi
          rm "$logs"
          echo "Device reported flashing succeeded. Device should be rebooting."
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
