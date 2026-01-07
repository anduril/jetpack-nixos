overlay:
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

  jetpackVersions = [ "5" "6" "7" ];

  checkValidSoms = soms: cfg.som == "generic" || lib.lists.any (s: lib.hasPrefix s cfg.som) soms;
  validSomsAssertion = majorVersion: soms: {
    assertion = cfg.majorVersion == majorVersion -> checkValidSoms soms;
    message = "Jetpack ${majorVersion} only supports som families: ${lib.strings.concatStringsSep " " soms} (or generic). Configured som: ${cfg.som}.";
  };

  jetpackAtLeast = lib.versionAtLeast cfg.majorVersion;
in
{
  imports = [
    ./capsule-updates.nix
    ./cuda.nix
    ./devices.nix
    ./flash-script.nix
    ./graphics.nix
    ./nvargus-daemon.nix
    ./nvfancontrol.nix
    ./nvidia-container-toolkit.nix
    ./nvpmodel.nix
    ./optee.nix
  ];

  options = {
    hardware.nvidia-jetpack = {
      enable = mkEnableOption "NVIDIA Jetson device support";

      majorVersion = mkOption {
        default = if lib.hasPrefix "thor" cfg.som then "7" else if cfg.som == "generic" || lib.hasPrefix "orin" cfg.som then "6" else "5";
        type = types.enum jetpackVersions;
        description = "Jetpack major version to use";
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
          "thor-agx"
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

          # Use this, if you would like to use Orin NX SOM with the original Xavier NX Devkit module (p3509-a02),
          "xavierNxDevkit"
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

      console.args = mkOption {
        internal = true;
        type = types.listOf types.str;
      };
    };
  };

  config = mkIf cfg.enable (lib.mkMerge [
    {
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
        (validSomsAssertion "5" [ "xavier" "orin" ])
        (validSomsAssertion "6" [ "orin" ])
        (validSomsAssertion "7" [ "thor" ])
        {
          assertion = ! (cfg.carrierBoard == "xavierNxDevkit" && cfg.som != "orin-nx");
          message = ''
            Invalid combination! XavierNxDevkit carrier board only valid with Orin NX SOM.
          '';
        }
      ];

      # Use mkOptionDefault so that we prevent conflicting with the priority that
      # `nixos-generate-config` uses.
      nixpkgs.hostPlatform = lib.mkOptionDefault "aarch64-linux";

      # Use mkBefore to ensure that our overlays get merged prior to any
      # downstream jetpack-nixos users. This should prevent a situation where a
      # user's overlay is merged before ours and that overlay depends on
      # something defined in our overlay.
      nixpkgs.overlays = mkBefore [
        overlay
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

      hardware.nvidia-jetpack.console.args = lib.mkMerge [
        (lib.optionals (checkValidSoms [ "xavier" "orin" ]) [
          "console=tty0" # Output to HDMI/DP. May need fbcon=map:0 as well
          "console=ttyTCU0,115200" # Provides console on "Tegra Combined UART" (TCU)
        ])
        (lib.optionals (checkValidSoms [ "thor" ]) [
          "console=tty0"
          "console=ttyUTC0,115200"
          "earlycon=tegra_utc,mmio32,0xc5a0000"
        ])
      ];

      boot.kernelPackages =
        (if cfg.kernel.realtime then
          pkgs.nvidia-jetpack.rtkernelPackages
        else
          pkgs.nvidia-jetpack.kernelPackages).extend pkgs.nvidia-jetpack.kernelPackagesOverlay;

      boot.kernelParams = [
        # Needed on Orin at least, but upstream has it for both
        "nvidia.rm_firmware_active=all"
      ]
      ++ lib.optionals cfg.console.enable cfg.console.args
      ++ lib.optionals (pkgs.nvidia-jetpack.l4tAtLeast "38") [
        "clk_ignore_unused"
      ];

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
      ] ++ lib.optionals (pkgs.nvidia-jetpack.l4tAtLeast "38") [
        "pwm-fan"
        "uas"
        "r8152"
        "phy-tegra194-p2u"
        "nvme-core"
        "tegra-bpmp-thermal"
        "pwm-tegra"
        "tegra_vblk"
        "tegra_hv_vblk_oops"
        "ufs-tegra"
        "nvpps"
        "pcie-tegra264"
        "nvethernet"
        "r8126"
        "r8168"
        "tegra_vnet"
        "rtl8852ce"
        "oak_pci"
      ];

      # See upstream default for this option, removes any modules that aren't enabled in JetPack kernel
      boot.initrd.luks.cryptoModules = lib.mkDefault [
        "aes"
        "aes_generic"
        "cbc"
        "xts"
        "sha1"
        "sha256"
        "sha512"
        "af_alg"
        "algif_skcipher"
      ];

      boot.kernelModules = if (jetpackAtLeast "7") then [ "nvidia-uvm" ] else [ "nvgpu" ];

      boot.extraModprobeConfig = lib.optionalString (jetpackAtLeast "6") ''
        options nvgpu devfreq_timer="delayed"
      '' + lib.optionalString (jetpackAtLeast "7") ''
        # from L4T-Ubuntu /etc/modprobe.d/nvidia-unifiedgpudisp.conf
        options nvidia NVreg_RegistryDwords="RMExecuteDevinitOnPmu=0;RMEnableAcr=1;RmCePceMap=0xffffff20;RmCePceMap1=0xffffffff;RmCePceMap2=0xffffffff;RmCePceMap3=0xffffffff;" NVreg_TegraGpuPgMask=512
        softdep nvidia pre: governor_pod_scaling post: nvidia-uvm
      '';

      boot.extraModulePackages = lib.optional (jetpackAtLeast "6") config.boot.kernelPackages.nvidia-oot-modules;

      hardware.firmware = with pkgs.nvidia-jetpack; [
        l4t-firmware
      ] ++ lib.optionals (lib.versionOlder cfg.majorVersion "7") [
        # Optional, but needed for pva_auth_allowlist firmware file used by VPI2
        cudaPackages.vpi-firmware
      ] ++ lib.optionals (l4tOlder "38") [
        l4t-xusb-firmware # usb firmware also present in linux-firmware package, but that package is huge and has much more than needed
      ] ++ lib.optionals (l4tAtLeast "38") (
        let
          getDriverDebs = prefix: (lib.filter (drv: lib.hasPrefix prefix (drv.pname or "")) (lib.attrValues pkgs.nvidia-jetpack.driverDebs));
          nvidiaDriverFirmwareDebs = getDriverDebs "nvidia-firmware-";
        in
        nvidiaDriverFirmwareDebs ++ [ l4t-firmware-openrm ]
      );

      boot.blacklistedKernelModules = [ "nouveau" ];

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

      services.udev.packages = [
        (pkgs.runCommand "jetson-udev-rules" { } ''
          install -D -t $out/etc/udev/rules.d ${pkgs.nvidia-jetpack.l4t-init}/etc/udev/rules.d/99-tegra-devices.rules
          sed -i \
            -e '/camera_device_detect/d' \
            -e 's#/bin/mknod#${lib.getExe' pkgs.coreutils "mknod"}#' \
            -e 's#/bin/rm#${lib.getExe' pkgs.coreutils "rm"}#' \
            -e 's#/bin/cut#${lib.getExe' pkgs.coreutils "cut"}#' \
            -e 's#/bin/grep#${lib.getExe pkgs.gnugrep}#' \
            -e 's#/bin/bash /etc/systemd/nvpower.sh#${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/systemd/nvpower.sh#' \
            -e 's#/bin/bash#${lib.getExe pkgs.bash}#' \
            $out/etc/udev/rules.d/99-tegra-devices.rules
        '')
      ];

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

      environment.systemPackages = with pkgs.nvidia-jetpack; [
        l4t-tools
        otaUtils # Tools for UEFI capsule updates
      ]
      # Tool to view GPU utilization.
      ++ lib.optionals (l4tAtLeast "36") [ nvidia-smi ]
      ++ lib.optionals (l4tAtLeast "38") [ l4t-bootloader-utils ];
    }
    (lib.mkIf (jetpackAtLeast "6") {
      hardware.deviceTree.dtbSource = config.boot.kernelPackages.devicetree;

      # Nvidia's jammy kernel has downstream apparmor patches which require "apparmor"
      # to appear sufficiently early in the `lsm=<list of security modules>` kernel argument
      security.lsm = lib.mkIf config.security.apparmor.enable (mkBefore [ "apparmor" ]);
    })
  ]);
}
