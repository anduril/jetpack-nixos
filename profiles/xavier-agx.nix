{ pkgs, lib, config, ... }:

# This represents the default configuration for just the Xavier AGX SoM, not including a carrier board
{
  config = lib.mkIf config.hardware.nvidia-jetpack.enable {
    services.nvpmodel.enable = lib.mkDefault true;
    services.nvpmodel.configFile = lib.mkDefault "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_t194.conf";
    services.nvfancontrol.configFile = lib.mkDefault "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p2888.conf";

    hardware.nvidia-jetpack.flashScriptOverrides = {
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
    };
  };
}
