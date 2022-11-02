{ pkgs, lib, config, ... }:

# This represents the default configuration for the Xavier NX SoM (production module)
{
  config = lib.mkIf config.hardware.nvidia-jetpack.enable {
    services.nvpmodel.enable = lib.mkDefault true;
    services.nvpmodel.configFile = lib.mkDefault "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_t194_p3668.conf";
    services.nvfancontrol.configFile = lib.mkDefault "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p3668.conf";

    hardware.nvidia-jetpack.flashScriptOverrides = {
      # Default to using the non-SD card (production module). The SD card variant is typically just for the devkit version
      targetBoard = lib.mkDefault "jetson-xavier-nx-devkit-emmc";
      partitionTemplate = lib.mkDefault "${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_l4t_t194_qspi_p3668.xml";
    };
  };
}
