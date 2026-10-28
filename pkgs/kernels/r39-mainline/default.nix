# Mainline patches for JetPack 7 / L4T r39:
# https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/BringYourOwnKernel.html
{ lib
, version
, realtime ? false
}:
let
  common = import ../r39/common-config.nix { inherit lib; mainline = true; };
in
common.kernelPatches ++ [
  {
    name = "jetpack-mainline-arch";
    patch = null;
    structuredExtraConfig =
      (lib.mapAttrs
        (_: value: lib.kernel.option value)
        (import ../common-arch.nix { inherit lib; }))
      // lib.genAttrs [
        "DRM_VC4_HDMI_CEC"
        "FSL_MC_UAPI_SUPPORT"
        "MT798X_WMAC"
        "NET_VENDOR_MEDIATEK"
        "ROCKCHIP_DW_HDMI_QP"
        "ROCKCHIP_DW_MIPI_DSI2"
        "SUN8I_DE2_CCU"
      ]
        (_: lib.mkForce (lib.kernel.option lib.kernel.no));
    # The ARM64 platform appends these legacy settings after structured config.
    extraConfig = ''
      ARCH_BCM2835? n
      BCM2835_MBOX? n
      BCM2835_WDT? n
      RASPBERRYPI_FIRMWARE? n
      RASPBERRYPI_POWER? n
      SERIAL_8250_BCM2835AUX? n
    '';
  }
  {
    name = "jetpack-mainline";
    patch = null;
    structuredExtraConfig = common.structuredExtraConfig // (with lib.kernel; {
      ARM64_PMEM = yes;
      # arm64's defconfig starts with modular DAX, limiting device-mapper to modules.
      BLK_DEV_DM = module;
      CRYPTO_ESSIV = module;
      DM_CRYPT = module;
      DM_VERITY = module;
      # Conflicts with the efi_pstore builtin default.
      PSTORE_RAM = no;
      # NVIDIA's r8168 is a stub on kernels >= 6.9.
      R8169 = module;
      # NVIDIA's nvmainline configuration skips rtl8852ce.
      RTW89 = module;
      RTW89_PCI = module;
      RTW89_8852CE = module;
      # NVIDIA's out-of-tree driver uses the same module name.
      SPI_TEGRA210_QUAD = no;
    });
  }
] ++ lib.optional realtime {
  name = "jetpack-mainline-realtime";
  patch = null;
  structuredExtraConfig = with lib.kernel; {
    PREEMPT = lib.mkForce (if lib.versionAtLeast version "6.13" then yes else no);
    PREEMPT_VOLUNTARY = lib.mkForce (option no);
    PREEMPT_LAZY = lib.mkForce (option no);
    PREEMPT_RT = yes;
  };
}
