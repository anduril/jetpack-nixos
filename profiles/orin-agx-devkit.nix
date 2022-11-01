{ pkgs, lib, ... }:

# This represents the default configuration for the Orin AGX attached to a devkit
{
  imports = [ ./orin-agx.nix ];

  services.nvfancontrol.enable = lib.mkDefault true;
}
