{ config, pkgs, lib, ... }:

# This represents the default configuration for the Xavier NX development module (with an SD-card slot), attached to a devkit
{
  imports = [ ./xavier-nx.nix ];

  config = lib.mkIf config.hardware.nvidia-jetpack.enable {
    services.nvfancontrol.enable = lib.mkDefault true;
    hardware.nvidia-jetpack.flashScriptOverrides.targetBoard = "jetson-xavier-nx-devkit-qspi";
  };
}
