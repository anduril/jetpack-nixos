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

  hardware.nvidia-jetpack.flashScriptOverrides = mkMerge [
    (mkIf (cfg.som == "orin-agx") {
      targetBoard = mkDefault "jetson-agx-orin-devkit";
      # We don't flash the sdmmc with kernel/initrd/etc at all. Just let it be a
      # regular NixOS machine instead of having some weird partition structure.
      partitionTemplate = mkDefault (pkgs.runCommand "flash.xml" {} ''
        sed -z \
          -E 's#<device[^>]*type="sdmmc_user"[^>]*>.*?</device>##' \
          <${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml \
          >$out
      '');
    })

    (mkIf (cfg.som == "xavier-agx") {
      targetBoard = lib.mkDefault "jetson-agx-xavier-devkit";
      # Remove unnecessary partitions to make it more like
      # flash_t194_uefi_sdmmc_min.xml, except also keep the A/B slots of
      # each partition
      partitionTemplate = let
        partitionsToRemove = [
          "kernel" "kernel-dtb" "reserved_for_chain_A_user"
          "kernel_b" "kernel-dtb_b" "reserved_for_chain_B_user"
          "RECNAME" "RECDTB-NAME" "RP1" "RP2" "RECROOTFS" # Recovery
          "esp" # L4TLauncher
        ];
      in pkgs.runCommand "flash.xml" {} ''
        sed -z \
          -E 's#<partition[^>]*type="(${lib.concatStringsSep "|" partitionsToRemove})"[^>]*>.*?</partition>##' \
          <${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_t194_sdmmc.xml \
          >$out
      '';
    })

    (mkIf (cfg.som == "xavier-nx" || cfg.som == "xavier-nx-emmc") {
      # We are inentionally using the flash_l4t_t194_qspi_p3668.xml for both
      # variants, instead of flash_l4t_t194_spi_emmc_p3668.xml for the emmc
      # variant as is done upstream, since they are otherwise identical, and we
      # don't want to flash partitions to the emmc.
      partitionTemplate = lib.mkDefault "${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_l4t_t194_qspi_p3668.xml";
    })

    {
      targetBoard = mkMerge [
        (mkIf (cfg.som == "xavier-nx") (mkDefault "jetson-xavier-nx-devkit-qspi"))
        (mkIf (cfg.som == "xavier-nx-emmc") (mkDefault "jetson-xavier-nx-devkit-emmc"))
      ];
    }
  ];
}
