{ mkRcmBootScript
, config
, flashInitrd
, lib
,
}:
let
  cfg = config.hardware.nvidia-jetpack;

  rcmScript = mkRcmBootScript {
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
    additionalDtbOverlays = lib.filter (path: (path.name or "") != "DefaultBootOrder.dtbo") cfg.flashScriptOverrides.additionalDtbOverlays;
  };
in
''
  ${rcmScript}

  echo
  echo "Jetson device should now be flashing and will reboot when complete."
  echo "You may watch the progress of this on the device's serial port"
''
