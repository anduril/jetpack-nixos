{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption types;

  cfg = config.hardware.nvidia-jetpack;

  jetpackAtLeast = lib.versionAtLeast cfg.majorVersion;
in
{
  options = {
    hardware.nvidia-jetpack.kernel = {
      useVendorProvided = mkOption {
        default = true;
        type = types.bool;
        description = "Use kernel provided by Nvidia's Jetson Linux";
      };

      realtime = mkOption {
        default = false;
        type = types.bool;
        description = "Enable PREEMPT_RT patches. Only has effect if useVendorProvided = true";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    boot = {
      kernelPackages = lib.mkIf cfg.kernel.useVendorProvided
        (if cfg.kernel.realtime then
          pkgs.nvidia-jetpack.rtkernelPackages
        else
          pkgs.nvidia-jetpack.kernelPackages);

      extraModulePackages = lib.optional (jetpackAtLeast "6") config.boot.kernelPackages.nvidia-oot-modules;

      blacklistedKernelModules = [ "nouveau" ];

      kernelModules = if (jetpackAtLeast "7") then [ "nvidia-uvm" ] else [ "nvgpu" ];

      kernelParams = [
        # Needed on Orin at least, but upstream has it for both
        "nvidia.rm_firmware_active=all"
      ] ++ lib.optionals (pkgs.nvidia-jetpack.l4tAtLeast "38") [
        "clk_ignore_unused"
      ];

      extraModprobeConfig = lib.optionalString (jetpackAtLeast "6") ''
        options nvgpu devfreq_timer="delayed"
      '' + lib.optionalString (jetpackAtLeast "7") ''
        # from L4T-Ubuntu /etc/modprobe.d/nvidia-unifiedgpudisp.conf
        options nvidia NVreg_RegistryDwords="RMExecuteDevinitOnPmu=0;RMEnableAcr=1;RmCePceMap=0xffffff20;RmCePceMap1=0xffffffff;RmCePceMap2=0xffffffff;RmCePceMap3=0xffffffff;"
        softdep nvidia pre: governor_pod_scaling post: nvidia-uvm
      '';

      initrd.includeDefaultModules = false; # Avoid a bunch of modules we may not get from tegra_defconfig
      initrd.availableKernelModules = [ "xhci-tegra" "ucsi_ccg" "typec_ucsi" "typec" ] # Make sure USB firmware makes it into initrd
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
      initrd.luks.cryptoModules = lib.mkDefault [
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
    };
  };
}
