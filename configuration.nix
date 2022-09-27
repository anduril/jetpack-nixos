{ config, lib, pkgs, ... }:
{
  imports = [
    ./module.nix
  ];

  boot.loader.systemd-boot.enable = true;

  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/boot"; fsType = "vfat"; };

  hardware.nvidia-jetpack.enable = true;

  hardware.opengl.enable = true;

  environment.systemPackages = [ pkgs.vulkan-tools ];

  services.xserver.enable = true;
}
