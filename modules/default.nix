{ options
, config
, lib
, pkgs
, ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.hardware.nvidia-jetpack;

  teeApplications = pkgs.symlinkJoin {
    name = "tee-applications";
    paths = cfg.firmware.optee.supplicant.trustedApplications;
  };

  supplicantPlugins = pkgs.symlinkJoin {
    name = "tee-supplicant-plugins";
    paths = cfg.firmware.optee.supplicant.plugins;
  };

  nvidiaDockerActive = with config.virtualisation; docker.enable && docker.enableNvidia;
  nvidiaPodmanActive = with config.virtualisation; podman.enable && podman.enableNvidia;
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
        # You can add your own som or carrierBoard by merging the enum type
        # with additional possibilies in an external NixOS module. See:
        # "Extensible option types" in the NixOS manual
        # The "generic" value signals that jetpack-nixos should try to maximize compatility across all varisnts. This may lead
        type = types.enum [
          "generic"
          "orin-agx"
          "orin-agx-industrial"
          "orin-nx"
          "orin-nano"
          "xavier-agx"
          "xavier-agx-industrial"
          "xavier-nx"
          "xavier-nx-emmc"
        ];
        default = "generic";
        description = ''
          Jetson SoM (System-on-Module) to target. Can be set to "generic" to target a generic jetson device, but some things may not work.
        '';
      };

      carrierBoard = mkOption {
        type = types.enum [
          "generic"
          "devkit"
        ];
        default = "generic";
        description = ''
          Jetson carrier board to target. Can be set to "generic" to target a generic jetson carrier board, but some things may not work.
        '';
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

      flasherPkgs = mkOption {
        type = options.nixpkgs.pkgs.type;
        default = import pkgs.path {
          system = "x86_64-linux";
          inherit (pkgs) config;
        };
        defaultText = ''
          import pkgs.path {
            system = "x86_64-linux";
            inherit (pkgs) config;
          }
        '';
        apply = p: p.appendOverlays pkgs.overlays;
        description = ''
          The package set that is used to build packages that run on an
          external host for purposes of flashing/fusing a Jetson device. This
          defaults to a package set that can run NVIDIA's pre-built x86
          binaries needed for flashing/fusing Jetson SOMs.
        '';
      };

      console.enable = mkOption {
        default = config.console.enable;
        defaultText = "config.console.enable";
        type = types.bool;
        description = "Enable boot.kernelParams default console configuration";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        # NixOS provides two main ways to feed a package set into a config:
        # 1. The options nixpkgs.hostPlatform/nixpkgs.buildPlatform, which are
        #    used to construct an import of nixpkgs.
        # 2. The option nixpkgs.pkgs (set by default if you use the pkgs.nixos
        #    function), which is a pre-configured import of nixpkgs.
        #
        # Regardless of how the package set is setup, it _must_ have its
        # hostPlatform compatible with aarch64 in order to run on the Jetson
        # platform.
        assertion = pkgs.stdenv.hostPlatform.isAarch64;
        message = ''
          NixOS config has an invalid package set for the Jetson platform. Try
          setting nixpkgs.hostPlatform to "aarch64-linux" or otherwise using an
          aarch64-linux compatible package set.
        '';
      }
      {
        assertion = nvidiaDockerActive -> lib.versionAtLeast config.virtualisation.docker.package.version "25";
        message = "Docker version < 25 does not support CDI";
      }
      {
        assertion = (nvidiaDockerActive || nvidiaPodmanActive) -> (!config.hardware.nvidia-container-toolkit.enable);
        message = "hardware.nvidia-container-toolkit.enable does not work with jetson devices (yet), use virtualisation.{docker,podman}.enableNvidia instead";
      }
    ];

    # Use mkOptionDefault so that we prevent conflicting with the priority that
    # `nixos-generate-config` uses.
    nixpkgs.hostPlatform = lib.mkOptionDefault "aarch64-linux";

    # Use mkBefore to ensure that our overlays get merged prior to any
    # downstream jetpack-nixos users. This should prevent a situation where a
    # user's overlay is merged before ours and that overlay depends on
    # something defined in our overlay.
    nixpkgs.overlays = lib.mkBefore [
      (import ../overlay.nix)
      (import ../overlay-with-config.nix config)
    ];

    boot.kernelPackages =
      if cfg.kernel.realtime then
        pkgs.nvidia-jetpack.rtkernelPackages
      else
        pkgs.nvidia-jetpack.kernelPackages;

    boot.kernelParams = [
      # Needed on Orin at least, but upstream has it for both
      "nvidia.rm_firmware_active=all"
    ]
    ++ lib.optionals cfg.console.enable [
      "console=tty0" # Output to HDMI/DP. May need fbcon=map:0 as well
      "console=ttyTCU0,115200" # Provides console on "Tegra Combined UART" (TCU)
    ]
    ++ lib.optional (lib.hasPrefix "xavier-" cfg.som || cfg.som == "generic") "video=efifb:off"; # Disable efifb driver, which crashes Xavier NX and possibly AGX

    boot.initrd.includeDefaultModules = false; # Avoid a bunch of modules we may not get from tegra_defconfig
    boot.initrd.availableKernelModules = [ "xhci-tegra" ]; # Make sure USB firmware makes it into initrd

    boot.kernelModules =
      [ "nvgpu" ]
      ++ lib.optionals cfg.modesetting.enable [
        "tegra-udrm" # For Xavier`
        "nvidia-drm" # For Orin
      ];

    boot.extraModprobeConfig = lib.optionalString cfg.modesetting.enable ''
      options tegra-udrm modeset=1
      options nvidia-drm modeset=1
    '';

    # For Orin. Unsupported with PREEMPT_RT.
    boot.extraModulePackages = lib.optional
      (
        !cfg.kernel.realtime
      )
       config.boot.kernelPackages.nvidia-oot ;
      # FIXME
      # config.boot.kernelPackages.nvgpu
      #config.boot.kernelPackages.nvidia-display-driver
      

    hardware.firmware = with pkgs.nvidia-jetpack; [
      l4t-firmware
      l4t-xusb-firmware # usb firmware also present in linux-firmware package, but that package is huge and has much more than needed
      cudaPackages.vpi2-firmware # Optional, but needed for pva_auth_allowlist firmware file used by VPI2
    ];

    hardware.deviceTree.enable = true;

    hardware.opengl.package = pkgs.nvidia-jetpack.l4t-3d-core;
    hardware.opengl.extraPackages =
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

    services.udev.packages = [
      (pkgs.runCommand "jetson-udev-rules" { } ''
        install -D -t $out/etc/udev/rules.d ${pkgs.nvidia-jetpack.l4t-init}/etc/udev/rules.d/99-tegra-devices.rules
        sed -i \
          -e '/camera_device_detect/d' \
          -e 's#/bin/mknod#${pkgs.coreutils}/bin/mknod#' \
          $out/etc/udev/rules.d/99-tegra-devices.rules
      '')
    ];

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

    # If we aren't using modesetting, we won't have a DRM device with the
    # "master-of-seat" tag, so "loginctl show-seat seat0" reports
    # "CanGraphical=false" and consequently lightdm doesn't start. We override
    # that here.
    services.xserver.displayManager.lightdm.extraConfig =
      lib.optionalString (!cfg.modesetting.enable)
        ''
          logind-check-graphical = false
        '';

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

    systemd.services.tee-supplicant =
      let
        args = lib.escapeShellArgs (
          [
            "--ta-path=${teeApplications}"
            "--plugin-path=${supplicantPlugins}"
          ]
          ++ cfg.firmware.optee.supplicant.extraArgs
        );
      in
      lib.mkIf cfg.firmware.optee.supplicant.enable {
        description = "Userspace supplicant for OPTEE-OS";
        serviceConfig = {
          ExecStart = "${pkgs.nvidia-jetpack.opteeClient}/bin/tee-supplicant ${args}";
          Restart = "always";
        };
        wantedBy = [ "multi-user.target" ];
      };

    environment.systemPackages = with pkgs.nvidia-jetpack; [
      l4t-tools
      otaUtils # Tools for UEFI capsule updates
    ];

    systemd.services.nvidia-cdi-generate = {
      enable = nvidiaDockerActive || nvidiaPodmanActive;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "cdi";
      };
      wantedBy = [ "multi-user.target" ];
      script =
        let
          exe = lib.getExe pkgs.nvidia-jetpack.nvidia-ctk;
        in
        ''
          ${exe} cdi generate \
            --nvidia-ctk-path=${exe} \
            --driver-root=${pkgs.nvidia-jetpack.containerDeps} \
            --ldconfig-path ${lib.getExe' pkgs.glibc "ldconfig"} \
            --dev-root=/ \
            --mode=csv \
            --csv.file=${pkgs.nvidia-jetpack.l4tCsv} \
            --output="$RUNTIME_DIRECTORY/jetpack-nixos"
        '';
    };

    # Used by libEGL_nvidia.so.0
    environment.etc."egl/egl_external_platform.d".source = "${pkgs.addOpenGLRunpath.driverLink}/share/egl/egl_external_platform.d/";
  };
}
