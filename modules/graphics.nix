{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkIf
    mkOption
    types
    ;

  cfg = config.hardware.nvidia-jetpack;

  checkValidSoms = soms: cfg.som == "generic" || lib.lists.any (s: lib.hasPrefix s cfg.som) soms;
in
{
  options = {
    hardware.nvidia-jetpack = {
      # I get this error when enabling modesetting
      # [   14.243184] NVRM gpumgrGetSomeGpu: Failed to retrieve pGpu - Too early call!.
      # [   14.243188] NVRM nvAssertFailedNoLog: Assertion failed: NV_FALSE @ gpu_mgr.c:
      modesetting.enable = mkOption {
        default = false;
        type = types.bool;
        description = "Enable kernel modesetting";
      };
    };

    # Allow disabling upstream's NVIDIA modules, which conflict with JetPack NixOS' driver handling.
    hardware.nvidia.enabled = lib.mkOption {
      readOnly = false;
    };
  };

  config = mkIf cfg.enable {
    # Disable efifb driver, which crashes Xavier NX and possibly AGX
    boot.kernelParams = lib.optional (checkValidSoms [ "xavier" ]) "video=efifb:off";

    boot.kernelModules =
      (lib.optional (cfg.modesetting.enable && checkValidSoms [ "xavier" ]) "tegra-udrm")
      ++ (lib.optional (cfg.modesetting.enable && checkValidSoms [ "orin" ]) "nvidia-drm");

    boot.extraModprobeConfig = lib.optionalString cfg.modesetting.enable ''
      options tegra-udrm modeset=1
      options nvidia-drm modeset=1 ${lib.optionalString (cfg.majorVersion == "6") "fbdev=1"}
    '';

    # For Orin on JP5. Unsupported with PREEMPT_RT.
    boot.extraModulePackages = lib.optional (cfg.majorVersion == "5" && !cfg.kernel.realtime)
      config.boot.kernelPackages.nvidia-display-driver;

    hardware.graphics.package = pkgs.nvidia-jetpack.l4t-3d-core;
    hardware.graphics.extraPackages =
      with pkgs.nvidia-jetpack;
      # l4t-core provides - among others - libnvrm_gpu.so and libnvrm_mem.so.
      # The l4t-core/lib directory is directly set in the DT_RUNPATH of
      # l4t-cuda's libcuda.so, thus the standard driver doesn't need them to be
      # added in ${driverLink}.
      #
      # However, this isn't the case for cuda_compat's driver currently, which
      # is why we're including this derivation in extraPackages.
      #
      # To avoid exposing a bunch of other unrelated libraries from l4t-core,
      # we're wrapping l4t-core in a derivation that only exposes the two
      # required libraries.
      #
      # Those libraries should ideally be directly accessible from the
      # DT_RUNPATH of cuda_compat's libcuda.so in the same way, but this
      # requires more integration between upstream Nixpkgs and jetpack-nixos.
      # When that happens, please remove l4tCoreWrapper below.
      let
        l4tCoreWrapper = pkgs.stdenv.mkDerivation {
          name = "l4t-core-wrapper";
          phases = [ "installPhase" ];
          installPhase = ''
            runHook preInstall

            mkdir -p $out/lib
            ln -s ${l4t-core}/lib/libnvrm_gpu.so $out/lib/libnvrm_gpu.so
            ln -s ${l4t-core}/lib/libnvrm_mem.so $out/lib/libnvrm_mem.so

            runHook postInstall
          '';
        };
      in
      [
        l4tCoreWrapper
        l4t-cuda
        l4t-nvsci # cuda may use nvsci
        l4t-gbm
        l4t-wayland
      ];

    # Used by libEGL_nvidia.so.0
    environment.etc."egl/egl_external_platform.d".source =
      "${pkgs.addDriverRunpath.driverLink}/share/egl/egl_external_platform.d/";

    hardware.nvidia = {
      # The JetPack stack isn't compatible with the upstream NVIDIA modules, which are meant for desktop and
      # datacenter GPUs. We need to disable them so they do not break our Jetson closures.
      # NOTE: Yes, they use "enabled" instead of "enable":
      # https://github.com/NixOS/nixpkgs/blob/ce01daebf8489ba97bd1609d185ea276efdeb121/nixos/modules/hardware/video/nvidia.nix#L27
      enabled = lib.mkForce false;

      # Since some modules use `hardware.nvidia.package` directly, we must ensure it is set to a reasonable package
      # to avoid bloating the Jetson closure with drivers for desktop or datacenter GPUs.
      # As an example, see:
      # https://github.com/NixOS/nixpkgs/blob/ce01daebf8489ba97bd1609d185ea276efdeb121/nixos/modules/services/hardware/nvidia-container-toolkit/default.nix#L173
      package = lib.mkForce config.hardware.graphics.package;
    };

    # Force the driver, since otherwise the fbdev or modesetting X11 drivers
    # may be used, which don't work and can interfere with the correct
    # selection of GLX drivers.
    services.xserver.drivers = lib.mkForce (
      lib.singleton {
        name = "nvidia";
        modules = [ pkgs.nvidia-jetpack.l4t-3d-core ];
        display = true;
        screenSection = ''
          Option "AllowEmptyInitialConfiguration" "true"
        '';
      }
    );

    # `videoDrivers` is normally used to populate `drivers`. Since we don't do that, make sure we have `videoDrivers`
    # contain the string "nvidia", as other modules scan the list to see what functionality to enable.
    # NOTE: Adding "nvidia" to `videoDrivers` is enough to automatically enable upstream NixOS' NVIDIA modules, since
    # there is a default driver package (the SBSA driver on aarch64-linux):
    # https://github.com/NixOS/nixpkgs/blob/ce01daebf8489ba97bd1609d185ea276efdeb121/nixos/modules/hardware/video/nvidia.nix#L8
    # Those modules would configure the device incorrectly, so we must disable `config.hardware.nvidia` separately.
    services.xserver.videoDrivers = [ "nvidia" ];

    # If we aren't using modesetting, we won't have a DRM device with the
    # "master-of-seat" tag, so "loginctl show-seat seat0" reports
    # "CanGraphical=false" and consequently lightdm doesn't start. We override
    # that here.
    services.xserver.displayManager.lightdm.extraConfig =
      lib.optionalString (!cfg.modesetting.enable)
        ''
          logind-check-graphical = false
        '';
  };
}
