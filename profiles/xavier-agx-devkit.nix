{ pkgs, config, lib, ... }:

# This represents the default configuration for the Xavier AGX attached to a devkit
{
  imports = [ ./xavier-agx.nix ];

  config = lib.mkIf config.hardware.nvidia-jetpack.enable {
    services.nvfancontrol.enable = lib.mkDefault true;
  };
}
