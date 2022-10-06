{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkForce
    mkIf
    mkOption
    mkOptionDefault;

  cfg = config.hardware.nvidia-jetpack;
in
{
  imports = [
    # https://developer.ridgerun.com/wiki/index.php/Xavier/JetPack_5.0.2/Performance_Tuning
    ./nvpmodel-module.nix
    ./nvfancontrol-module.nix
    ./nvargus-daemon-module.nix
  ];

  options = {
    hardware.nvidia-jetpack = {
      enable = mkEnableOption "NVIDIA Jetson device support";

      maxClock.enable = mkEnableOption "max clock speed";
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [ (import ./overlay.nix) ];

    boot.kernelPackages = pkgs.linuxPackagesFor pkgs.nvidia-jetpack.kernel;

    boot.kernelParams = [
      "console=ttyTCU0,115200" # Provides console on "Tegra Combined UART" (TCU)
      "console=tty0" # Output to HDMI/DP
      "fbcon=map:0" # Needed for HDMI/DP
    ];

    boot.initrd.includeDefaultModules = false; # Avoid a bunch of modules we may not get from tegra_defconfig
    boot.initrd.availableKernelModules = [ "xhci-tegra" ]; # Make sure USB firmware makes it into initrd
    boot.initrd.kernelModules = [ "nvgpu tegra-udrm" ]; # Load these drivers early. Unclear if this is necessary
    # Enable DRM/KMS
    boot.extraModprobeConfig = ''
      options tegra-udrm modeset=1
    '';

    hardware.firmware = with pkgs.nvidia-jetpack; [
      l4t-firmware
      l4t-xusb-firmware # usb firmware also present in linux-firmware package, but that package is huge and has much more than needed
      cudaPackages.vpi2 # Optional, but needed for pva_auth_allowlist firmware file used by VPI2
    ];

    hardware.deviceTree.enable = true;

    hardware.opengl.package = pkgs.nvidia-jetpack.l4t-3d-core;
    hardware.opengl.extraPackages = with pkgs.nvidia-jetpack; [
      l4t-cuda
      l4t-nvsci # cuda may use nvsci
      l4t-gbm l4t-wayland
    ];

    # libGLX_nvidia.so.0 complains without this
    hardware.opengl.setLdLibraryPath = true;

    services.udev.packages = [
      (pkgs.runCommand "jetson-udev-rules" {} ''
        install -D -t $out/etc/udev/rules.d ${pkgs.nvidia-jetpack.l4t-init}/etc/udev/rules.d/99-tegra-devices.rules
        sed -i \
          -e '/camera_device_detect/d' \
          -e 's#/bin/mknod#${pkgs.coreutils}/bin/mknod#' \
          $out/etc/udev/rules.d/99-tegra-devices.rules
      '')
    ];

    # Override other drivers, fbdev seems to conflict
    services.xserver.drivers = mkForce (lib.singleton {
      name = "nvidia";
      modules = [ pkgs.nvidia-jetpack.l4t-3d-core ];
      display = true;
    });

    # Used by libjetsonpower.so, which is used by nvfancontrol at least.
    environment.etc."nvpower/libjetsonpower".source = "${pkgs.nvidia-jetpack.l4t-tools}/etc/nvpower/libjetsonpower";

    # https://developer.ridgerun.com/wiki/index.php/Xavier/JetPack_5.0.2/Performance_Tuning
    systemd.services.jetson_clocks = mkIf cfg.maxClock.enable {
      enable = true;
      description = "Set maximum clock speed";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.nvidia-jetpack.l4t-tools}/bin/jetson_clocks";
        ReadWritePaths = [ "/sys" ];
        ProtectSystem = "strict";
      };
      after = [ "nvpmodel.service" ];
      wantedBy = [ "multi-user.target" ];
    };

    environment.systemPackages = with pkgs.nvidia-jetpack; [ l4t-tools ];
  };
}
