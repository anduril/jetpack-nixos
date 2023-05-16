{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkForce
    mkIf
    mkOption
    mkOptionDefault
    types;

  cfg = config.hardware.nvidia-jetpack;
in
{
  imports = [
    # https://developer.ridgerun.com/wiki/index.php/Xavier/JetPack_5.0.2/Performance_Tuning
    ./nvpmodel.nix
    ./nvfancontrol.nix
    ./nvargus-daemon.nix
    ./flash-script.nix
    ./devices.nix
  ];

  options = {
    hardware.nvidia-jetpack = {
      enable = mkEnableOption "NVIDIA Jetson device support";

      # I get this error when enabling modesetting
      # [   14.243184] NVRM gpumgrGetSomeGpu: Failed to retrieve pGpu - Too early call!.
      # [   14.243188] NVRM nvAssertFailedNoLog: Assertion failed: NV_FALSE @ gpu_mgr.c:
      modesetting.enable = mkOption {
        default = false;
        type = types.bool;
        description = "Enable kernel modesetting";
      };

      maxClock = mkOption {
        default = false;
        type = types.bool;
        description = "Always run at maximum clock speed";
      };

      som = mkOption {
        default = null;
        # You can add your own som or carrierBoard by merging the enum type
        # with additional possibilies in an external NixOS module. See:
        # "Extensible option types" in the NixOS manual
        type = types.nullOr (types.enum [ "orin-agx" "orin-nx" "orin-nano" "xavier-agx" "xavier-nx" "xavier-nx-emmc" ]);
        description = "Jetson SoM (System-on-Module) to target. Can be null to target a generic jetson device, but some things may not work.";
      };

      carrierBoard = mkOption {
        default = null;
        type = types.nullOr (types.enum [ "devkit" ]);
        description = "Jetson carrier board to target.";
      };

      kernel.realtime = mkOption {
        default = false;
        type = types.bool;
        description = "Enable PREEMPT_RT patches";
      };

      mountFirmwareEsp = mkOption {
        default = true;
        type = types.bool;
        description = "Whether to mount the ESP partition on eMMC under /opt/nvidia/esp on Xavier AGX platforms. Needed for capsule updates";
        internal = true;
      };
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [ (import ../overlay.nix) ];

    boot.kernelPackages =
      if cfg.kernel.realtime
      then pkgs.nvidia-jetpack.rtkernelPackages
      else pkgs.nvidia-jetpack.kernelPackages;

    boot.kernelParams = [
      "console=tty0" # Output to HDMI/DP
      "fbcon=map:0" # Needed for HDMI/DP
      "video=efifb:off" # Disable efifb driver, which crashes Xavier AGX/NX

      "console=ttyTCU0,115200" # Provides console on "Tegra Combined UART" (TCU)

      # Needed on Orin at least, but upstream has it for both
      "nvidia.rm_firmware_active=all"
    ];

    boot.initrd.includeDefaultModules = false; # Avoid a bunch of modules we may not get from tegra_defconfig
    boot.initrd.availableKernelModules = [ "xhci-tegra" ]; # Make sure USB firmware makes it into initrd

    boot.kernelModules = [
      "nvgpu"
    ] ++ lib.optionals cfg.modesetting.enable [
      "tegra-udrm" # For Xavier`
      "nvidia-drm" # For Orin
    ];

    boot.extraModprobeConfig = lib.optionalString cfg.modesetting.enable ''
      options tegra-udrm modeset=1
      options nvidia-drm modeset=1
    '';

    # For Orin. Unsupported with PREEMPT_RT.
    boot.extraModulePackages = lib.optional (!cfg.kernel.realtime) config.boot.kernelPackages.nvidia-display-driver;

    hardware.firmware = with pkgs.nvidia-jetpack; [
      l4t-firmware
      l4t-xusb-firmware # usb firmware also present in linux-firmware package, but that package is huge and has much more than needed
      cudaPackages.vpi2-firmware # Optional, but needed for pva_auth_allowlist firmware file used by VPI2
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

    services.xserver.drivers = lib.mkBefore (lib.singleton {
      name = "nvidia";
      modules = [ pkgs.nvidia-jetpack.l4t-3d-core ];
      display = true;
      screenSection = ''
        Option "AllowEmptyInitialConfiguration" "true"
      '';
    });

    # Used by libjetsonpower.so, which is used by nvfancontrol at least.
    environment.etc."nvpower/libjetsonpower".source = "${pkgs.nvidia-jetpack.l4t-tools}/etc/nvpower/libjetsonpower";

    # Include nv_tegra_release, just so we can tell what version our NixOS machine was built from.
    environment.etc."nv_tegra_release".source = "${pkgs.nvidia-jetpack.l4t-core}/etc/nv_tegra_release";

    # https://developer.ridgerun.com/wiki/index.php/Xavier/JetPack_5.0.2/Performance_Tuning
    systemd.services.jetson_clocks = mkIf cfg.maxClock {
      enable = true;
      description = "Set maximum clock speed";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.nvidia-jetpack.l4t-tools}/bin/jetson_clocks";
      };
      after = [ "nvpmodel.service" ];
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.tee-supplicant = {
      description = "Userspace supplicant for OPTEE-OS";
      serviceConfig = {
        ExecStart = "${pkgs.nvidia-jetpack.opteeClient}/bin/tee-supplicant";
        Restart = "always";
      };
      wantedBy = [ "multi-user.target" ];
    };

    environment.systemPackages = with pkgs.nvidia-jetpack; [
      l4t-tools
      otaUtils # Tools for UEFI capsule updates
    ];

    # Used by libEGL_nvidia.so.0
    environment.etc."egl/egl_external_platform.d".source = "/run/opengl-driver/share/egl/egl_external_platform.d/";
  };
}
