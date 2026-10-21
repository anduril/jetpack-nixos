# Mainline kernel for JetPack 7 / L4T r39, following NVIDIA's "Bring Your Own Kernel" guide:
# https://docs.nvidia.com/jetson/archives/r39.2/DeveloperGuide/SD/Kernel/BringYourOwnKernel.html
#
# Unlike ../r39, nothing is taken from NVIDIA's kernel-noble tree. Everything that
# is not upstream comes from the separate out-of-tree sources built by
# ../r39/oot-modules.nix (with kernel_name=nvmainline) and ../r39/devicetree.nix.
#
# The "upstream patches" table in the guide lists two commits that were only in
# linux-next when it was written (92a511a568e4 and 8ddfc01ace51, simplefb
# power-domains / memory-region support). Both were merged in v6.8, so they are
# already part of any sensible baseKernel and are not applied here.
#
# baseKernel defaults to 6.18 LTS rather than linuxPackages_latest: nvidia-oot is
# written for 6.8 and does not compile against 7.x (ASoC pcm_construct, dma_fence.lock,
# of_gpio.h, drm_atomic_private_obj_init, ...). 6.18 builds with the patches in ../r39.
{ lib
, baseKernel ? linuxPackages_6_18.kernel
, linuxPackages_6_18
, realtime ? false
, kernelPatches ? [ ]
, structuredExtraConfig ? { }
, argsOverride ? { }
, buildLinux
, ...
}@args:
assert lib.assertMsg (lib.versionAtLeast baseKernel.version "6.9")
  "r39-mainline requires a baseKernel >= 6.9 (got ${baseKernel.version})";
buildLinux ((removeAttrs args [ "baseKernel" "linuxPackages_6_18" ]) // {
  inherit (baseKernel) src version modDirVersion;
  extraMeta.branch = lib.versions.majorMinor baseKernel.version;

  defconfig = "defconfig";
  ignoreConfigErrors = true;

  kernelPatches = baseKernel.kernelPatches ++ [
    {
      # Required by the guide before building, not set in mainline's defconfig.
      name = "bring-your-own-kernel-config";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        ARM64_PMEM = yes;
      };
    }
    {
      name = "erofs";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        EROFS_FS = yes;
        MMC_SDHCI_PCI = module;
      };
    }
  ] ++ kernelPatches;

  structuredExtraConfig = with lib.kernel; {
    # Same as r39: nvidia's driver fails with the 32M default from common-config.nix.
    CMA_SIZE_MBYTES = lib.mkForce (freeform "64");

    # nvidia-oot (configs/Makefile.config.nvmainline) builds its own spi-tegra210-quad;
    # drop the in-tree one so the module names don't collide.
    SPI_TEGRA210_QUAD = no;
  } // (import ../common-arch.nix { inherit lib; })
  // lib.optionalAttrs realtime {
    PREEMPT_VOLUNTARY = lib.mkForce no;
    PREEMPT_RT = yes;
  } // structuredExtraConfig;
} // argsOverride)
