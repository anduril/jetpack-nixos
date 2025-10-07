{ mkRcmBootScript
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

  rcmScript = mkRcmBootScript {
    kernelPath = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
    initrdPath = "${flashInitrd}/initrd";
    kernelCmdline = lib.concatStringsSep " " ([
      "sdhci_tegra.en_boot_part_access=1"
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

  expectScript = writeText "expect-initrd-flash" ''
    set modem /dev/serial/by-id/${serialPortId}

    send_user "connecting to $modem\n"
    # --log-strip -> Strip control characters and escape sequences
    # --mute -> Mute tio messages
    spawn -noecho "${lib.getExe tio}" --log-strip --mute "$modem"
    set timeout 900
    set failed 0
    expect {
      "Flashing platform firmware successful" {
        exit
      }
      "Flashing platform firmware unsuccessful" {
        set timeout 2
        set failed 1
        exp_continue
      }
      "Entering console" {
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
''
  ${rcmScript}

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

  if ! ${lib.getExe expect} -f ${expectScript} ; then
    echo "Flashing may have failed"
    exit 1
  fi
  echo "Device reported flashing succeeded. Device should be rebooting."
''
