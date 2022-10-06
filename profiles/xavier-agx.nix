{ pkgs, lib, ... }:

let
  inherit (lib)
    mkDefault;
in
{
  services.nvpmodel.enable = mkDefault true;
  services.nvpmodel.configFile = mkDefault "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_t194.conf";
  services.nvfancontrol.enable = mkDefault true;
  services.nvfancontrol.configFile = mkDefault "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol/nvfancontrol_p2888.conf";
}
