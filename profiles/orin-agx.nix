{ pkgs, lib, config, ... }:

# This represents the default configuration for just the Orin AGX SoM, not including a carrier board
{
  config = lib.mkIf config.hardware.nvidia-jetpack.enable {
    services.nvpmodel.enable = lib.mkDefault true;
    services.nvpmodel.configFile = lib.mkDefault "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_p3701_0000.conf";
    services.nvfancontrol.configFile = lib.mkDefault "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p3701_0000.conf";

    hardware.nvidia-jetpack.flashScriptOverrides = {
      targetBoard = lib.mkDefault "jetson-agx-orin-devkit";
      # We don't flash the sdmmc with kernel/initrd/etc at all. Just let it be a
      # regular NixOS machine instead of having some weird partition structure.
      partitionTemplate = lib.mkDefault (pkgs.runCommand "flash.xml" {} ''
        sed -z \
          -E 's#<device[^>]*type="sdmmc_user"[^>]*>.*?</device>##' \
          <${pkgs.nvidia-jetpack.bspSrc}/bootloader/t186ref/cfg/flash_t234_qspi_sdmmc.xml \
          >$out
      '');
    };
  };
}
