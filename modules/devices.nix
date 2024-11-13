{ pkgs, config, lib, ... }:

# Configuration specific to particular SoM or carrier boardsl
let
  inherit (lib)
    mkDefault
    mkIf
    mkMerge;

  cfg = config.hardware.nvidia-jetpack;

  nvpModelConf = {
    orin-agx = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_p3701_0000.conf";
    orin-agx-industrial = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_p3701_0008.conf";
    orin-nx = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_p3767_0000.conf";
    orin-nano = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_p3767_0003.conf";
    xavier-agx = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_t194.conf";
    xavier-agx-industrial = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_t194_agxi.conf";
    xavier-nx = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_t194_p3668.conf";
    xavier-nx-emmc = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_t194_p3668.conf";
  };

  nvfancontrolConf = {
    orin-agx = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p3701_0000.conf";
    orin-agx-industrial = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p3701_0008.conf";
    orin-nx = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p3767_0000.conf";
    orin-nano = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p3767_0000.conf";
    xavier-agx = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p2888.conf";
    xavier-agx-industrial = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p2888.conf";
    xavier-nx = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p3668.conf";
    xavier-nx-emmc = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p3668.conf";
  };

  # Extract from linux firmware so that the 1GiB+ size of linux-firmware
  # doesn't become a runtime dependency in a nixos system's closure.
  extractLinuxFirmware = name: paths: (pkgs.runCommand name { }
    (lib.concatLines (map
      # all files in linux-firmware are read-only
      (firmwarePath: ''
        if [[ -f $(realpath ${pkgs.linux-firmware}/lib/firmware/${firmwarePath}) ]]; then
          install -Dm0444 \
            --target-directory=$(dirname $out/lib/firmware/${firmwarePath}) \
            ${pkgs.linux-firmware}/lib/firmware/${firmwarePath}
        else
          echo "WARNING: lib/firmware/${firmwarePath} does not exist in linux-firmware ${pkgs.linux-firmware.version}"
        fi
      ''
      )
      paths)));
in
lib.mkMerge [{
  # Turn on nvpmodel if we have a config for it.
  services.nvpmodel.enable = mkIf (nvpModelConf ? "${cfg.som}") (mkDefault true);
  services.nvpmodel.configFile = mkIf (nvpModelConf ? "${cfg.som}") (mkDefault nvpModelConf.${cfg.som});

  # Set fan control service if we have a config for it
  services.nvfancontrol.configFile = mkIf (nvfancontrolConf ? "${cfg.som}") (mkDefault nvfancontrolConf.${cfg.som});
  # Enable the fan control service if it's a devkit
  services.nvfancontrol.enable = mkIf (cfg.carrierBoard == "devkit") (mkDefault true);

  hardware.nvidia-jetpack.flashScriptOverrides =
    let
      # Remove unnecessary partitions to make it more like
      # flash_t194_uefi_sdmmc_min.xml, except also keep the A/B slots on each
      # partition
      basePartitionsToRemove = [
        "kernel"
        "kernel-dtb"
        "reserved_for_chain_A_user"
        "kernel_b"
        "kernel-dtb_b"
        "reserved_for_chain_B_user"
        "APP" # Original rootfs
        "RECNAME"
        "RECNAME_alt"
        "RECDTB-NAME"
        "RECDTB-NAME_alt"
        "RP1"
        "RP2"
        "RECROOTFS" # Recovery
        "esp_alt"
      ];
      # Keep the esp partition on eMMC for the Xavier AGX, which needs to have it exist on the Xavier AGX to update UEFI vars via DefaultVariableDxe
      # https://forums.developer.nvidia.com/t/setting-uefi-variables-using-the-defaultvariabledxe-only-works-if-esp-is-on-emmc-but-not-on-an-nvme-drive/250254
      xavierAgxPartitionsToRemove = basePartitionsToRemove;
      defaultPartitionsToRemove = basePartitionsToRemove ++ [ "esp" ];
      # It's unclear why cross-compiles appear to need pkgs.buildPackages.xmlstarlet instead of just xmlstarlet in nativeBuildInputs
      filterPartitions = partitionsToRemove: basefile:
        let
          xpathMatch = lib.concatMapStringsSep " or " (p: "@name = \"${p}\"") partitionsToRemove;
        in
        pkgs.runCommand "flash.xml" { nativeBuildInputs = [ pkgs.buildPackages.xmlstarlet ]; } ''
          xmlstarlet ed -d '//partition[${xpathMatch}]' ${basefile} >$out
        '';
    in
    mkMerge [
      (mkIf (cfg.som == "orin-agx") {
        targetBoard = mkDefault "jetson-agx-orin-devkit";
        # We don't flash the sdmmc with kernel/initrd/etc at all. Just let it be a
        # regular NixOS machine instead of having some weird partition structure.
        partitionTemplate = mkDefault "${pkgs.nvidia-jetpack.flash-tools}/bootloader/generic/cfg/flash_t234_qspi.xml";
      })

      (mkIf (cfg.som == "orin-agx-industrial") {
        targetBoard = mkDefault "jetson-agx-orin-devkit-industrial";
        # Remove the sdmmc part of this flash.xmo file. The industrial spi part is still different
        partitionTemplate = mkDefault (pkgs.runCommand "flash.xml" { nativeBuildInputs = [ pkgs.buildPackages.xmlstarlet ]; } ''
          xmlstarlet ed -d '//device[@type="sdmmc_user"]' ${pkgs.nvidia-jetpack.bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc_industrial.xml >$out
        '');
      })

      (mkIf (cfg.som == "orin-nx" || cfg.som == "orin-nano") {
        targetBoard = mkDefault "jetson-orin-nano-devkit";
        # Use this instead if you want to use the original Xavier NX Devkit module (p3509-a02)
        #targetBoard = mkDefault "p3509-a02+p3767-0000";
        partitionTemplate = mkDefault "${pkgs.nvidia-jetpack.bspSrc}/bootloader/generic/cfg/flash_t234_qspi.xml";
      })

      (mkIf (cfg.som == "xavier-agx") {
        targetBoard = mkDefault "jetson-agx-xavier-devkit";
        # Remove unnecessary partitions to make it more like
        # flash_t194_uefi_sdmmc_min.xml, except also keep the A/B slots of
        # each partition
        partitionTemplate = mkDefault (filterPartitions xavierAgxPartitionsToRemove "${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_t194_sdmmc.xml");
      })

      (mkIf (cfg.som == "xavier-agx-industrial") {
        targetBoard = mkDefault "jetson-agx-xavier-industrial";
        # Remove the sdmmc part of this flash.xml file. The industrial spi part is still different
        partitionTemplate = mkDefault (pkgs.runCommand "flash.xml" { nativeBuildInputs = [ pkgs.buildPackages.xmlstarlet ]; } ''
          xmlstarlet ed -d '//device[@type="sdmmc_user"]' ${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_l4t_t194_spi_emmc_jaxi.xml >$out
        '');
      })

      (mkIf (cfg.som == "xavier-nx") {
        targetBoard = mkDefault "jetson-xavier-nx-devkit";
        partitionTemplate = mkDefault (filterPartitions defaultPartitionsToRemove "${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_l4t_t194_spi_sd_p3668.xml");
      })

      (mkIf (cfg.som == "xavier-nx-emmc") {
        targetBoard = mkDefault "jetson-xavier-nx-devkit-emmc";
        partitionTemplate = mkDefault (filterPartitions defaultPartitionsToRemove "${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_l4t_t194_spi_emmc_p3668.xml");
      })
    ];

  boot.kernelPatches = lib.mkIf (cfg.som == "orin-nx") [
    {
      name = "disable-usb-otg";
      patch = null;
      # TODO: Having these options enabled on the Orin NX currently causes a
      # kernel panic with a failure in tegra_xudc_unpowergate. We should figure
      # this out
      extraStructuredConfig = with lib.kernel; {
        USB_OTG = no;
        USB_GADGET = no;
      };
    }
  ];
}
  (lib.mkIf (cfg.som == "xavier-agx" && cfg.mountFirmwareEsp) {
    # On Xavier AGX, setting UEFI variables requires having the ESP partition on the eMMC:
    # https://forums.developer.nvidia.com/t/setting-uefi-variables-using-the-defaultvariabledxe-only-works-if-esp-is-on-emmc-but-not-on-an-nvme-drive/250254
    # We don't mount this at /boot, because we still want to allow the user to have their ESP part on NVMe, or whatever else.
    fileSystems."/opt/nvidia/esp" = lib.mkDefault {
      device = "/dev/disk/by-partlabel/esp";
      fsType = "vfat";
      options = [ "nofail" ];
      # Since we have NO_ESP_IMG=1 while formatting, the script doesn't
      # actually create an FS here, so we'll do it automatically
      autoFormat = true;
      formatOptions =
        if (lib.versionAtLeast config.system.nixos.release "23.05") then
          null
        else
          "-F 32 -n ESP";
    };
  })
  (lib.mkIf (lib.any (som: som == cfg.som) [ "orin-nx" "orin-nano" ]) {
    hardware.firmware = [
      # From https://github.com/OE4T/linux-tegra-5.10/blob/20443c6df8b9095e4676b4bf696987279fac30a9/drivers/net/ethernet/realtek/r8169_main.c#L38
      (extractLinuxFirmware "r8168-firmware" [
        "rtl_nic/rtl8168d-1.fw"
        "rtl_nic/rtl8168d-2.fw"
        "rtl_nic/rtl8168e-1.fw"
        "rtl_nic/rtl8168e-2.fw"
        "rtl_nic/rtl8168e-3.fw"
        "rtl_nic/rtl8168f-1.fw"
        "rtl_nic/rtl8168f-2.fw"
        "rtl_nic/rtl8105e-1.fw"
        "rtl_nic/rtl8402-1.fw"
        "rtl_nic/rtl8411-1.fw"
        "rtl_nic/rtl8411-2.fw"
        "rtl_nic/rtl8106e-1.fw"
        "rtl_nic/rtl8106e-2.fw"
        "rtl_nic/rtl8168g-2.fw"
        "rtl_nic/rtl8168g-3.fw"
        "rtl_nic/rtl8168h-2.fw" # wanted by orin-nx and orin-nano
        "rtl_nic/rtl8168fp-3.fw"
        "rtl_nic/rtl8107e-2.fw"
        "rtl_nic/rtl8125a-3.fw"
        "rtl_nic/rtl8125b-2.fw"
        "rtl_nic/rtl8126a-2.fw"
      ])
    ];
  })
  (lib.mkIf (cfg.som == "orin-agx") {
    hardware.firmware = lib.optionals
      (config.hardware.bluetooth.enable
        || config.networking.wireless.enable
        || config.networking.wireless.iwd.enable) [
      # From https://github.com/OE4T/linux-tegra-5.10/blob/20443c6df8b9095e4676b4bf696987279fac30a9/drivers/net/wireless/realtek/rtw88/rtw8822c.c#L4398
      (extractLinuxFirmware "rtw88-firmware" [
        "rtw88/rtw8822c_fw.bin"
        "rtw88/rtw8822c_wow_fw.bin"
      ])
    ];
  })]
