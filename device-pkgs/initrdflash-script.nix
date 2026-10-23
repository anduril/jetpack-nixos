{ mkRcmBootScript
, mkRcmBootArgs
, mkFlashCmdTools
, useFlashCmd
, writeShellApplication
, buildPackages
, nvidia-jetpack
, socType
, signedFirmware
, config
, flashInitrd
, lib
, l4tMajorMinorPatchVersion
, writeText
, deviceTree
, tio
, expect
,
}:
let
  cfg = config.hardware.nvidia-jetpack;
  inherit (flashInitrd.passthru) manufacturer product serialnumber;
  serialPortId = "usb-${manufacturer}_${product}_${serialnumber}-if00";


  forceXusbPeripheralDts =
    let
      overridePaths = {
        "39" = {
          thor = {
            xudcPadctlPath = "bus@0/padctl@a808680000";
            xudcPath = "bus@0/usb@a808670000";
          };
          orin = {
            xudcPadctlPath = "bus@0/padctl@3520000";
            xudcPath = "bus@0/usb@3550000";
          };
        };
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
    in
    writeText "dts" ''
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
  forceXusbPeripheralDtbo = deviceTree.compileDTS {
    # We force USB port to peripheral mode, in case the carrier board doesn't support OTG
    # Fortunately, the USB controller is all in the SoC, so we can override it directly here
    name = "force-xusb-peripheral.dtbo";
    dtsFile = forceXusbPeripheralDts;
  };

  rcmBootArgs = {
    kernelPath = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
    initrdPath =
      if useFlashCmd then "${flashInitrd}/initrd"
      else "${builtins.placeholder "out"}/libexec/initrd";
    kernelCmdline = lib.concatStringsSep " " ([
      "sdhci_tegra.en_boot_part_access=1"
      "clk_ignore_unused"
      "rd.systemd.unit=jetson-flash.target"
      "rd.systemd.gpt_auto=no"
      "noresume"
    ] ++ cfg.console.args);
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
    additionalDtbOverlays = (lib.filter (path: (path.name or "") != "DefaultBootOrder.dtbo") cfg.flashScriptOverrides.additionalDtbOverlays) ++ [ forceXusbPeripheralDtbo ];
  };

  rcmScript = mkRcmBootScript (rcmBootArgs // lib.optionalAttrs useFlashCmd {
    flashTools = "${builtins.placeholder "out"}/libexec/rcm";
  });
  preparedRcm = mkFlashCmdTools (mkRcmBootArgs rcmBootArgs);
  payload = if useFlashCmd then "libexec/rcm/bootloader/boot.img" else "libexec/initrd";

  expectScript = writeText "expect-initrd-flash" ''
    set modem /dev/serial/by-id/${serialPortId}

    send_user "connecting to $modem\n"
    # --log-strip -> Strip control characters and escape sequences
    # --mute -> Mute tio messages
    spawn -noecho "${lib.getExe tio}" --log-strip --mute "$modem"
    set timeout ${builtins.toString cfg.flashScriptOverrides.initrdFlashCompletionTimeoutSeconds}
    set failed 0
    expect {
      "Flashing platform firmware successful" {
        exit
      }
      "Flashing platform firmware unsuccessful" {
        set failed 1
        exp_continue
      }
      "root account is locked" {
        exit 1
      }
      -re {Press Enter for (system )?maintenance} {
        interact {
          # \003 is Ctrl-C
          \003   exit 1
          ~~
        }
      }
      timeout {
        if {$failed == 1} {
          exit 1
        } else {
          send_user "connection to device timed out\n"
          exit 2
        }
      }
      eof {
        send_user "Connection to device failed: $expect_out(buffer)"
        exit 2
      }
    }
  '';
in
(writeShellApplication {
  name = "initrd-flash-${cfg.name}";
  text = ''
    (
      cd "${builtins.placeholder "out"}"
      ${lib.getExe' buildPackages.coreutils "sha256sum"} \
        --check --status share/jetpack/flash-payload.sha256
    )
    ${rcmScript}

    echo
    echo "Jetson device should now be flashing and will reboot when complete."

    # TODO(eberman): maybe stop assuming /dev/serial/by-id is present
    # It'll be populated with udev, so most Linux systems will work fine
    echo -n "Waiting up to ${builtins.toString cfg.flashScriptOverrides.initrdFlashSerialEnumerateTimeoutSeconds}s for Jetson device to appear via USB"

    counter=0
    until [[ -e /dev/serial/by-id/${serialPortId} || $counter -gt ${builtins.toString (cfg.flashScriptOverrides.initrdFlashSerialEnumerateTimeoutSeconds * 2)} ]] ; do
      echo -n "."
      sleep 0.5
      ((++counter))
    done
    echo

    if [ ! -e /dev/serial/by-id/${serialPortId} ] ; then
      echo "Jetson device not detected, please monitor the serial port or wait 5-15 minutes"
      exit 2
    fi

    if ! ${lib.getExe expect} -f ${expectScript} ; then
      echo "Flashing may have failed"
      exit 1
    fi
    echo "Device reported flashing succeeded. Device should be rebooting."
  '';
  meta.platforms = [ "x86_64-linux" ];
  meta.outputsToInstall = [ "out" ];
}).overrideAttrs (prev: {
  outputs = [ "out" "pcr" ];
  buildCommand = prev.buildCommand + ''
    mkdir -p "$out/libexec" "$out/share/jetpack" "$pcr"
    ${if useFlashCmd then ''
      mkdir -p "$out/libexec/rcm"
      cp -r ${preparedRcm}/. "$out/libexec/rcm/"
    '' else ''
      cp ${flashInitrd}/initrd "$out/libexec/initrd"
    ''}
    # The signed directory is only an archive lookup key, not another input.
    ${lib.getExe nvidia-jetpack.firmwareMeasurements} \
      ${socType} initrdFlashScript "$out/${payload}" "$out/${payload}" \
      --signed-directory ${builtins.unsafeDiscardStringContext (toString signedFirmware)} \
      > "$pcr/measurements.json"
    cp "$pcr/measurements.json" "$out/share/jetpack/measurements.json"
    (
      cd "$out"
      ${lib.getExe' buildPackages.coreutils "sha256sum"} ${payload} \
        > share/jetpack/flash-payload.sha256
    )
  '';
})
