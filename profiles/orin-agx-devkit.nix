{ pkgs, lib, config, ... }:

# This represents the default configuration for the Orin AGX attached to a devkit
{
  imports = [ ./orin-agx.nix ];

  config = lib.mkIf config.hardware.nvidia-jetpack.enable {
    services.nvfancontrol.enable = lib.mkDefault true;
  };
}
