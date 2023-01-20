{ pkgs, config, lib, ... }:

# Configuration specific to particular SoM or carrier boardsl
let
  inherit (lib)
    mkDefault
    mkIf
    mkMerge;

  cfg = config.hardware.nvidia-jetpack;

  nvpModelConf = {
    "orin-agx" = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_p3701_0000.conf";
    "xavier-agx" = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_t194.conf";
    "xavier-nx" = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_t194_p3668.conf";
    "xavier-nx-emmc" = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_t194_p3668.conf";
  };

  nvfancontrolConf = {
    "orin-agx" = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p3701_0000.conf";
    "xavier-agx" = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p2888.conf";
    "xavier-nx" ="${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p3668.conf";
    "xavier-nx-emmc" ="${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p3668.conf";
  };
in {
  # Turn on nvpmodel if we have a config for it.
  services.nvpmodel.enable = mkIf (cfg.som != null && nvpModelConf ? "${cfg.som}") (mkDefault true);
  services.nvpmodel.configFile = mkIf (cfg.som != null && nvpModelConf ? "${cfg.som}") (mkDefault nvpModelConf.${cfg.som});

  # Set fan control service if we have a config for it
  services.nvfancontrol.configFile = mkIf (cfg.som != null && nvfancontrolConf ? "${cfg.som}") (mkDefault nvfancontrolConf.${cfg.som});
  # Enable the fan control service if it's a devkit
  services.nvfancontrol.enable = mkIf (cfg.carrierBoard == "devkit") (mkDefault true);

  hardware.nvidia-jetpack.flashScriptOverrides = let
    # Remove unnecessary partitions to make it more like
    # flash_t194_uefi_sdmmc_min.xml, except also keep the A/B slots on each
    # partition
    partitionsToRemove = [
      "kernel" "kernel-dtb" "reserved_for_chain_A_user"
      "kernel_b" "kernel-dtb_b" "reserved_for_chain_B_user"
      "APP" # Original rootfs
      "RECNAME" "RECDTB-NAME" "RP1" "RP2" "RECROOTFS" # Recovery
      "esp" # L4TLauncher
    ];
    xpathMatch = lib.concatMapStringsSep " or " (p: "@name = \"${p}\"") partitionsToRemove;
    # It's unclear why cross-compiles appear to need pkgs.buildPackages.xmlstarlet instead of just xmlstarlet in nativeBuildInputs
    filterPartitions = basefile: pkgs.runCommand "flash.xml" { nativeBuildInputs = [ pkgs.buildPackages.xmlstarlet ]; } ''
      xmlstarlet ed -d '//partition[${xpathMatch}]' ${basefile} >$out
    '';
  in mkMerge [
    (mkIf (cfg.som == "orin-agx") {
      targetBoard = mkDefault "jetson-agx-orin-devkit";
      # We don't flash the sdmmc with kernel/initrd/etc at all. Just let it be a
      # regular NixOS machine instead of having some weird partition structure.
      partitionTemplate = mkDefault (pkgs.runCommand "flash.xml" { nativeBuildInputs = [ pkgs.buildPackages.xmlstarlet ]; } ''
        xmlstarlet ed -d '//device[@type="sdmmc_user"]' \
          ${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml \
          >$out
      '');
    })

    (mkIf (cfg.som == "xavier-agx") {
      targetBoard = mkDefault "jetson-agx-xavier-devkit";
      # Remove unnecessary partitions to make it more like
      # flash_t194_uefi_sdmmc_min.xml, except also keep the A/B slots of
      # each partition
      partitionTemplate = mkDefault (filterPartitions "${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_t194_sdmmc.xml");
    })

    (mkIf (cfg.som == "xavier-nx") {
      targetBoard = mkDefault "jetson-xavier-nx-devkit";
      partitionTemplate = mkDefault (filterPartitions "${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_l4t_t194_spi_sd_p3668.xml");
    })

    (mkIf (cfg.som == "xavier-nx-emmc") {
      targetBoard = mkDefault "jetson-xavier-nx-devkit-emmc";
      partitionTemplate = mkDefault (filterPartitions "${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_l4t_t194_spi_emmc_p3668.xml");
    })
  ];
}
