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
