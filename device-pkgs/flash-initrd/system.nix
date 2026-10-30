# A standalone NixOS stage 1 environment for flashing platform firmware.
{ extraModules
, flashFromDevice
, signedFirmware
, usbIdentity
}:

{ config, lib, pkgs, utils, ... }:

{
  system.stateVersion = lib.trivial.release;

  boot = {
    loader.grub.enable = false;

    initrd = {
      includeDefaultModules = false;

      kernelModules =
        let
          kernelVersion = lib.versions.majorMinor config.system.build.kernel.version;
          spiModules = if kernelVersion == "5.10" then [ "qspi_mtd" "spi_tegra210_qspi" "at24" "spi_nor" ] else [ "mtdblock" "spi_tegra210_quad" ];
          usbModules = lib.optionals (kernelVersion != "5.10") [ "libcomposite" "udc-core" "tegra-xudc" "xhci-tegra" "u_serial" "usb_f_acm" ];
        in
        lib.unique (spiModules ++ usbModules ++ extraModules);

      services.udev.rules = lib.mkMerge [
        # Use the device USB role.
        ''ACTION=="add", SUBSYSTEM=="usb_role", ATTRS{of_node/connector/label}=="usb-recovery", TEST=="role", ATTR{role}="device"''

        # Create a stable symlink for the Jetson USB serial gadget.
        ''SUBSYSTEM=="tty", KERNEL=="ttyGS*", SYMLINK+="jetson-flash-serial"''

        # Keep the USB root hubs awake.
        ''ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", KERNEL=="usb*", ATTRS{of_node/compatible}=="nvidia,tegra*-xusb", TEST=="power/control", ATTR{power/control}="on"''
      ];

      systemd = {
        enable = true;
        root = null;

        tpm2.enable = false; # JetPack 5/6 kernels lack the TPM drivers NixOS adds by default.

        additionalUpstreamUnits = [ "usb-gadget.target" ];

        targets = {
          initrd.enable = false;
          jetson-flash = {
            requires = [ "basic.target" ];
            after = [ "basic.target" ];
          };
        };

        storePaths = [
          signedFirmware

          # makeInitrdNG cannot discover store references inside shell scripts.
          # Link the helper's runtime closure so it copies those dependencies too.
          (pkgs.runCommand "jetson-flash-runtime"
            {
              __structuredAttrs = true;
              exportReferencesGraph.graph = [ flashFromDevice ];
              nativeBuildInputs = [ pkgs.buildPackages.jq ];
            }
            ''
              mkdir -p "$out"
              jq -r '.graph[].path' "$NIX_ATTRS_JSON_FILE" | while IFS= read -r storePath; do
                ln -s "$storePath" "$out/''${storePath##*/}"
              done
            '')

          pkgs.gt
        ];

        contents."/etc/jetson-flash.scheme".source = (pkgs.formats.libconfig { }).generate "jetson-flash.scheme" {
          attrs = {
            idVendor = 7531; # 0x1d6b
            idProduct = 260; # 0x0104
          };
          strings = [ (usbIdentity // { lang = 1033; }) ]; # 0x0409, US English
          functions.acm_usb0 = { instance = "usb0"; type = "acm"; };
          configs = [{
            id = 1;
            name = "c";
            functions = [{ name = "acm.usb0"; function = "acm_usb0"; }];
          }];
        };

        services = {
          jetson-usb-gadget = {
            wantedBy = [ "usb-gadget.target" ];
            requires = [ "sys-kernel-config.mount" ];
            after = [ "sys-kernel-config.mount" ];
            onFailure = [ "rescue.target" ];
            unitConfig = {
              OnFailureJobMode = "isolate";
              IgnoreOnIsolate = true;
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = [ pkgs.gt ];
            script = ''
              gt load --off /etc/jetson-flash.scheme g.1
              # force into device mode if OTG and something is up with automatic detection
              if [ -w /sys/class/usb_role/usb2-0-role-switch/role ] ; then
                echo device > /sys/class/usb_role/usb2-0-role-switch/role
              fi
              gt enable g.1
            '';
            postStop = ''
              if [[ -d /sys/kernel/config/usb_gadget/g.1 ]]; then
                gt rm -rf g.1
              fi
            '';
          };

          jetson-flash = {
            wantedBy = [ "jetson-flash.target" ];
            requires = [ "${utils.escapeSystemdPath "/dev/jetson-flash-serial"}.device" ];
            after = [ "jetson-usb-gadget.service" "${utils.escapeSystemdPath "/dev/jetson-flash-serial"}.device" ];
            onFailure = [ "rescue.target" ];
            unitConfig = {
              OnFailureJobMode = "isolate";
              SuccessAction = "reboot";
            };
            serviceConfig = {
              Type = "oneshot";
            };
            path = [ pkgs.coreutils ];
            script = ''
              set -o pipefail

              # Allow USB enumeration and the host serial connection to complete.
              sleep 5

              exec 3>/dev/jetson-flash-serial
              stty --file=/dev/jetson-flash-serial raw -echo

              '${lib.getExe flashFromDevice}' '${signedFirmware}' 2>&1 | tee /proc/self/fd/3
              echo "Flashing platform firmware successful. Rebooting now." | tee /proc/self/fd/3
            '';
          };

          rescue = {
            after = [ "jetson-usb-gadget.service" ];
            environment.CONSOLE = "/dev/jetson-flash-serial"; # sulogin falls back to the system consoles if this tty cannot be opened.
            preStart = ''
              reportFailure() {
                echo "Flashing platform firmware unsuccessful."
              }
              reportFailure
              if [[ -e "$CONSOLE" ]]; then
                reportFailure >"$CONSOLE"
              fi
            '';
          };
        };
      };
    };
  };
}
