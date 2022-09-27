{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkIf
    mkEnableOption;

  cfg = config.hardware.nvidia-jetpack;
in
{
  options = {
    hardware.nvidia-jetpack = {
      enable = mkEnableOption "NVIDIA Jetson device support";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages = pkgs.linuxPackagesFor pkgs.nvidia-jetpack.kernel;

    boot.kernelParams = [
      "console=ttyTCU0,115200" # Provides console on "Tegra Combined UART" (TCU)
      "console=tty0" # Output to HDMI/DP
      "fbcon=map:0" # Needed for HDMI/DP
    ];

    boot.initrd.availableKernelModules = [ "xhci-tegra" ]; # Make sure USB firmware makes it into initrd

    hardware.firmware = with pkgs.nvidia-jetpack; [
      l4t-firmware
      l4t-xusb-firmware # usb firmware also present in linux-firmware package, but that package is huge and has much more than needed
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
    services.xserver.drivers = lib.mkForce (lib.singleton {
      name = "nvidia";
      modules = [ pkgs.nvidia-jetpack.l4t-3d-core ];
      display = true;
    });

    # TODO: Performance nvpmodel, CPUs, etc.
    # https://developer.ridgerun.com/wiki/index.php/Xavier/JetPack_5.0.2/Performance_Tuning
  };
}
