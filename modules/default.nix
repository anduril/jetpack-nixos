{ options
, config
, lib
, pkgs
, ...
}:

let
  inherit (lib)
    mkBefore
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.hardware.nvidia-jetpack;

  jetpackVersions = [ "5" "6" ];

  teeApplications = pkgs.symlinkJoin {
    name = "tee-applications";
    paths = cfg.firmware.optee.supplicant.trustedApplications;
  };

  supplicantPlugins = pkgs.symlinkJoin {
    name = "tee-supplicant-plugins";
    paths = cfg.firmware.optee.supplicant.plugins;
  };

  checkValidSoms = soms: cfg.som == "generic" || lib.lists.any (s: lib.hasPrefix s cfg.som) soms;
  validSomsAssertion = majorVersion: soms: {
    assertion = cfg.majorVersion == majorVersion -> checkValidSoms soms;
    message = "Jetpack ${majorVersion} only supports som families: ${lib.strings.concatStringsSep " " soms} (or generic). Configured som: ${cfg.som}.";
  };

  jetpackAtLeast = lib.versionAtLeast cfg.majorVersion;
in
{
  imports = [
    # https://developer.ridgerun.com/wiki/index.php/Xavier/JetPack_5.0.2/Performance_Tuning
    ./nvpmodel.nix
    ./nvfancontrol.nix
    ./nvargus-daemon.nix
    ./flash-script.nix
    ./devices.nix
    (lib.modules.mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "container-toolkit" "enable" ] [ "hardware" "nvidia-container-toolkit" "enable" ])
  ];

  options = {
    # Allow disabling upstream's NVIDIA modules, which conflict with JetPack NixOS' driver handling.
    hardware.nvidia.enabled = lib.mkOption {
      readOnly = false;
    };

    hardware.nvidia-jetpack = {
      enable = mkEnableOption "NVIDIA Jetson device support";

      majorVersion = mkOption {
        default = if cfg.som == "generic" || lib.hasPrefix "orin" cfg.som then "6" else "5";
        type = types.enum jetpackVersions;
        description = "Jetpack major version to use";
      };

      configureCuda = mkOption {
        default = true;
        type = types.bool;
        description = ''
          Configures the instance of Nixpkgs used for the system closure for Jetson devices.

          When enabled, Nixpkgs is instantiated with `config.cudaSupport` set to `true`, so all packages
          are built with CUDA support enabled. Additionally, `config.cudaCapabilities` is set based on the
          value of `hardware.nvidia-jetpack.som`, producing binaries targeting the specific Jetson SOM.
        '';
      };

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

      super = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether to enable "super mode" for Jetson Orin NX and Nano
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

  config = mkIf cfg.enable (lib.mkMerge [
    {
      assertions = lib.mkMerge [
        [
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
          (validSomsAssertion "5" [ "xavier" "orin" ])
          (validSomsAssertion "6" [ "orin" ])
        ]
        (
          let
            inherit (pkgs.cudaPackages) cudaMajorMinorVersion cudaAtLeast cudaOlder;
          in
          # If NixOS has been configured with CUDA support, add additional assertions to make sure CUDA packages
            # being built have a chance of working.
          lib.mkIf pkgs.config.cudaSupport [
            {
              assertion = !cudaOlder "11.4";
              message = "JetPack NixOS does not support CUDA 11.3 or earlier: `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
            }
            {
              assertion = cfg.majorVersion == "5" -> (cudaAtLeast "11.4" && cudaOlder "12.3");
              message = "JetPack NixOS 5 supports CUDA 11.4 (natively) - 12.2 (with `cuda_compat`): `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
            }
            {
              assertion = cfg.majorVersion == "6" -> (cudaAtLeast "12.4" && cudaOlder "13.0");
              message = "JetPack NixOS 6 supports CUDA 12.4 (natively) - 12.9 (with `cuda_compat`): `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
            }
            {
              assertion = !cudaAtLeast "13.0";
              message = "JetPack NixOS does not support CUDA 13.0 or later: `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
            }
          ]
        )
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
        (
          let
            otherJetpacks = builtins.filter (v: v != cfg.majorVersion) jetpackVersions;
          in
          final: prev:
            let
              mkWarnJetpack = v: lib.warn "nvidia-jetpack${v} is unsupported when nixos is configured to use Jetpack ${cfg.majorVersion}" prev."nvidia-jetpack${v}";
            in
            # NOTE: While the version of `cudaPackages` drives the version of `nvidia-jetpack`, we need to set them both here since
              # overlay-with-config needs to reference `prev.nvidia-jetpack`, so we can't wait for it to resolve via `final`.
            {
              nvidia-jetpack = final."nvidia-jetpack${cfg.majorVersion}";
              cudaPackages = final."cudaPackages_${lib.versions.major final."nvidia-jetpack${cfg.majorVersion}".cudaMajorMinorVersion}";
            }
            # warn if anyone tries to evaluate non-default nvidia-jetpack package sets, but keep them around to avoid missing attribute errors.
            // builtins.listToAttrs (builtins.map
              (v: { name = "nvidia-jetpack${v}"; value = mkWarnJetpack v; })
              otherJetpacks)
        )
        (import ../overlay-with-config.nix config)
      ];

      # Advertise support for CUDA.
      nixpkgs.config = mkIf cfg.configureCuda (mkBefore {
        cudaSupport = true;
        cudaCapabilities =
          let
            isGeneric = cfg.som == "generic";
            isXavier = lib.hasPrefix "xavier-" cfg.som;
            isOrin = lib.hasPrefix "orin-" cfg.som;
          in
          lib.optionals (isXavier || isGeneric) [ "7.2" ] ++ lib.optionals (isOrin || isGeneric) [ "8.7" ];
      });

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
      boot.initrd.availableKernelModules = [ "xhci-tegra" "ucsi_ccg" "typec_ucsi" "typec" ] # Make sure USB firmware makes it into initrd
        ++ lib.optionals (pkgs.nvidia-jetpack.l4tAtLeast "36") [
        "nvme"
        "tegra_mce"
        "phy-tegra-xusb"
        "i2c-tegra"
        "fusb301"
        # PCIe for nvme, ethernet, etc.
        "phy_tegra194_p2u"
        "pcie_tegra194"
        # Ethernet for AGX
        "nvpps"
        "nvethernet"
      ];

      boot.kernelModules =
        [ "nvgpu" ]
        ++ lib.optionals (cfg.modesetting.enable && checkValidSoms [ "xavier" ]) [ "tegra-udrm" ]
        ++ lib.optionals (cfg.modesetting.enable && checkValidSoms [ "orin" ]) [ "nvidia-drm" ];

      boot.extraModprobeConfig = lib.optionalString (jetpackAtLeast "6") ''
        options nvgpu devfreq_timer="delayed"
      '' + lib.optionalString cfg.modesetting.enable ''
        options tegra-udrm modeset=1
        options nvidia-drm modeset=1 ${lib.optionalString (cfg.majorVersion == "6") "fbdev=1"}
      '';

      boot.extraModulePackages =
        # For Orin. Unsupported with PREEMPT_RT.
        lib.optionals (cfg.majorVersion == "5" && !cfg.kernel.realtime)
          [ config.boot.kernelPackages.nvidia-display-driver ]
        ++
        lib.optionals (jetpackAtLeast "6") [
          (pkgs.nvidia-jetpack.kernelPackages.nvidia-oot-modules.overrideAttrs {
            inherit (config.boot.kernelPackages) kernel;
          })
        ];

      hardware.firmware = with pkgs.nvidia-jetpack; [
        l4t-firmware
        l4t-xusb-firmware # usb firmware also present in linux-firmware package, but that package is huge and has much more than needed
        cudaPackages.vpi-firmware # Optional, but needed for pva_auth_allowlist firmware file used by VPI2
      ];

      hardware.deviceTree.enable = true;
      hardware.deviceTree.dtboBuildExtraIncludePaths = {
        "5" = let dtsTree = "${config.hardware.deviceTree.kernelPackage.src}/nvidia"; in lib.mkMerge [
          [
            "${dtsTree}/soc/tegra/kernel-include"
            "${dtsTree}/platform/tegra/common/kernel-dts"
          ]
          (lib.optionals (checkValidSoms [ "xavier" ]) [
            "${dtsTree}/soc/t18x/kernel-include"
            "${dtsTree}/soc/t18x/kernel-dts"
            "${dtsTree}/platform/t18x/common/kernel-dts"
          ])
          (lib.optionals (checkValidSoms [ "orin" ]) [
            "${dtsTree}/soc/t23x/kernel-include"
            "${dtsTree}/soc/t23x/kernel-dts"
            "${dtsTree}/platform/t23x/common/kernel-dts"
            "${dtsTree}/platform/t23x/automotive/kernel-dts/common/linux/"
          ])
        ];
        # See DTC_INCLUDE inside ${gitRepos."kernel-devicetree"}/generic-dts/Makefile
        "6" = let dtsTree = "${config.hardware.deviceTree.dtbSource.src}/hardware/nvidia"; in [
          # SOC independent common include
          "${dtsTree}/tegra/nv-public"

          # SOC T23X specific common include
          "${dtsTree}/t23x/nv-public/include/kernel"
          "${dtsTree}/t23x/nv-public/include/nvidia-oot"
          "${dtsTree}/t23x/nv-public/include/platforms"
          "${dtsTree}/t23x/nv-public"
        ];
      }.${cfg.majorVersion};

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

      hardware.nvidia-container-toolkit.enable = lib.mkDefault (
        with config.virtualisation;
        docker.enable && docker.enableNvidia || podman.enable && podman.enableNvidia
      );

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

      # Used by libjetsonpower.so, which is used by nvfancontrol at least.
      environment.etc."nvpower/libjetsonpower".source = "${pkgs.nvidia-jetpack.l4t-tools}/etc/nvpower/libjetsonpower";

      # Include nv_tegra_release, just so we can tell what version our NixOS machine was built from.
      environment.etc."nv_tegra_release".source = "${pkgs.nvidia-jetpack.l4t-core}/etc/nv_tegra_release";

      # For some unknown reason, the libnvscf.so library has a dlopen call to a hard path:
      # `/usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0`
      # This causes loading errors for libargus applications and the nvargus-daemon.
      # Errors will look like this:
      # SCF: Error NotSupported: Failed to load EGL library
      # To fix this, create a symlink to the correct EGL library in the above directory.
      #
      # An alternative approach would be to wrap the library with an LD_PRELOAD to a dlopen call
      # that replaces the hardcoded path with the correct path.
      # However, since dynamic library symbol lookups start with the calling binary,
      # this override would have to happen at the binary level, which means every binary
      # would need to be wrapped. This is less desirable than simply adding the following symlink.
      systemd.services.create-libegl-symlink =
        let
          linkEglLib = pkgs.writeShellScriptBin "link-egl-lib" ''
            ${lib.getExe' pkgs.coreutils "mkdir"} -p /usr/lib/aarch64-linux-gnu/tegra-egl
            ${lib.getExe' pkgs.coreutils "ln"} -s /run/opengl-driver/lib/libEGL_nvidia.so.0 /usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0
          '';
        in
        {
          enable = true;
          description = "Create a symlink for libEGL_nvidia.so.0 at /usr/lib/aarch64-linux-gnu/tegra-egl/";
          unitConfig = {
            ConditionPathExists = "!/usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0";
          };
          serviceConfig = {
            type = "oneshot";
            ExecStart = lib.getExe linkEglLib;
          };
          wantedBy = [ "multi-user.target" ];
        };


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

      hardware.nvidia-jetpack.firmware.optee.supplicant.trustedApplications = [ ]
        ++ lib.optional cfg.firmware.optee.pkcs11Support pkgs.nvidia-jetpack.pkcs11Ta
        ++ lib.optional cfg.firmware.optee.xtest pkgs.nvidia-jetpack.opteeXtest;

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
      ] ++ lib.optional cfg.firmware.optee.xtest pkgs.nvidia-jetpack.opteeXtest
      # Tool to view GPU utilization.
      ++ lib.optional (l4tAtLeast "36") nvidia-smi;

      # Used by libEGL_nvidia.so.0
      environment.etc."egl/egl_external_platform.d".source =
        "${pkgs.addDriverRunpath.driverLink}/share/egl/egl_external_platform.d/";
    }
    (lib.mkIf (jetpackAtLeast "6")
      {
        hardware.deviceTree.dtbSource = pkgs.nvidia-jetpack.kernelPackages.devicetree;

        # Nvidia's jammy kernel has downstream apparmor patches which require "apparmor"
        # to appear sufficiently early in the `lsm=<list of security modules>` kernel argument
        security.lsm = lib.mkIf config.security.apparmor.enable (lib.mkBefore [ "apparmor" ]);
      })
    (mkIf config.hardware.nvidia-container-toolkit.enable {
      systemd.services.nvidia-container-toolkit-cdi-generator = {
        # TODO: Upstream waits on `system-udev-settle.service`:
        # https://github.com/NixOS/nixpkgs/blob/ce01daebf8489ba97bd1609d185ea276efdeb121/nixos/modules/services/hardware/nvidia-container-toolkit/default.nix#L240
        # That's not recommended; instead we should have udev rules for the devices we care about so we can wait on them specifically.
        wants = [ "modprobe@nvgpu.service" ];
        after = [ "modprobe@nvgpu.service" ];

        # TODO: A previous version of this service included the following note:
        #
        #  # Wait until all devices are present before generating CDI
        #  # configuration. Also ensure that we aren't passing any directories
        #  # or glob patterns to udevadm (Jetpack 6 CSVs seem to add these,
        #  # though the Jetpack 5 CSVs do not have them).
        #  udevadm wait --settle --timeout 10 $(find ${pkgs.nvidia-jetpack.l4tCsv}/ -type f -exec grep '/dev/' {} \; | grep -v -e '\*' -e 'by-path' | cut -d',' -f2 | tr -d '\n') || true
        #
        # Investigate if globs pose a problem for JetPack 5/6.

        # TODO: This should be upstreamed.
        before = lib.mkMerge [
          (mkIf config.virtualisation.docker.enable [ "docker.service" ])
          (mkIf config.virtualisation.podman.enable [ "podman.service" ])
        ];
      };

      hardware.nvidia-container-toolkit = {
        # TODO: Issues to address in nvidia-container-toolkit-cdi-generator:
        # - Warning about "Failed to locate symlink /etc/vulkan/icd.d/nvidia_icd.json" on the host
        # - Log reports "Generated CDI spec with version 0.8.0" but actual CDI JSON shows `"cdiVersion": "0.5.0"`

        csv-files =
          let
            inherit (pkgs.nvidia-jetpack) l4tCsv;
          in
          lib.map (fileName: "${l4tCsv}/${fileName}") l4tCsv.fileNames;

        # Must be set to "csv" when `csv-files` are provided.
        discovery-mode = lib.mkForce "csv";

        # Unsupported.
        mount-nvidia-docker-1-directories = lib.mkForce false;

        # Unsupported as Jetson doesn't provide the same binaries as other platforms; ours are captured by the CSV
        # files in l4tCsv and are always included in the container.
        mount-nvidia-executables = lib.mkForce false;

        extraArgs = [
          # Jetson requires `--driver-root`
          "--driver-root"
          pkgs.nvidia-jetpack.containerDeps.outPath
          # `--dev-root` defaults to `/dev`, but it should be root
          "--dev-root"
          "/"
          # The cdi generation creates a hook for us mounting "libcuda.so.1::/usr/lib/aarch64-linux-gnu/tegra/libcuda.so".
          # Because the provided CSV does about the same thing, and we cannot disable the hook, we ignore the CSV entry.
          "--csv.ignore-pattern"
          "/usr/lib/aarch64-linux-gnu/tegra/libcuda.so" # For JetPack 5
          "--csv.ignore-pattern"
          "/usr/lib/aarch64-linux-gnu/nvidia/libcuda.so" # For JetPack 6
        ];

        # NOTE: The upstream NixOS module for `nvidia-container-toolkit` includes `hardware.nvidia.package` in the list
        # of mounts, but we don't want that because that's for desktop/datacenter GPU drivers, so we use `lib.mkForce`
        # to make the list of mounts anew.
        mounts =
          let
            makePassthroughMount = path: {
              hostPath = path;
              containerPath = path;
            };

            # For reference, the packages used to create driverLink are here:
            # https://github.com/NixOS/nixpkgs/blob/ce01daebf8489ba97bd1609d185ea276efdeb121/nixos/modules/hardware/graphics.nix#L10
            driverLinkConstituents = [
              config.hardware.graphics.package
              # Recall that `config.hardware.graphics.extraPackages` creates l4tCoreWrapper inline, which
              # symlinks to l4t-core. In order for those symlinks to resolve, their target must also be included
              # in the list of mounts; as such, we need l4t-core.
              pkgs.nvidia-jetpack.l4t-core
            ]
            ++ config.hardware.graphics.extraPackages;
          in
          lib.mkForce (
            lib.map makePassthroughMount [
              "${lib.getLib pkgs.glibc}/lib"
              "${lib.getLib pkgs.glibc}/lib64"
              pkgs.addDriverRunpath.driverLink
            ]
            # NOTE: Is it not enough to include the driverLink -- the symlinks to the Nix store won't resolve.
            # We must include all the the packages which go into producing it as well.
            # TODO: This can/should be upstreamed. Ultimately, this behavior is very similar to the
            # nix-required-mounts hook, which can add the GPU to the sandbox, where we also need the closure
            # of all packages involved.
            ++ lib.map (drv: makePassthroughMount drv.outPath) driverLinkConstituents
          );
      };
    })
  ]);
}
