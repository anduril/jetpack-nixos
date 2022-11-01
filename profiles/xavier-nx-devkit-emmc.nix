{ config, pkgs, lib, ... }:

# This represents the default configuration for the Xavier NX production module (without an SD-card slot), attached to a devkit
{
  imports = [ ./xavier-nx.nix ];

  services.nvfancontrol.enable = mkDefault true;
}
