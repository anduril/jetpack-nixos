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
# already part of any sensible baseLinuxPackages and are not applied here.
#
# baseLinuxPackages (the kernel package set to build from) defaults to 6.18 LTS rather
# than linuxPackages_latest: nvidia-oot is
# written for 6.8 and does not compile against 7.x (ASoC pcm_construct, dma_fence.lock,
# of_gpio.h, drm_atomic_private_obj_init, ...). 6.18 builds with the patches in ../r39.
{ lib
, linuxKernel
, baseLinuxPackages ? linuxKernel.packages.linux_6_18
, realtime ? false
, kernelPatches ? [ ]
, structuredExtraConfig ? { }
, argsOverride ? { }
, buildLinux
, ...
}@args:
assert lib.assertMsg (lib.versionAtLeast baseLinuxPackages.kernel.version "6.9")
  "r39-mainline requires a baseLinuxPackages kernel >= 6.9 (got ${baseLinuxPackages.kernel.version})";
buildLinux ((removeAttrs args [ "baseLinuxPackages" "linuxKernel" ]) // {
  inherit (baseLinuxPackages.kernel) src version modDirVersion;
  extraMeta.branch = lib.versions.majorMinor baseLinuxPackages.kernel.version;

  defconfig = "defconfig";
  ignoreConfigErrors = true;

  # Same as r39: don't build every driver as a module, the shared ../r39/common-config.nix
  # lists what NixOS and the OOT modules need.
  autoModules = false;
  features = { };

  kernelPatches = baseLinuxPackages.kernel.kernelPatches ++ [
    {
      # Same as r39; see the comment in ../r39/common-config.nix.
      name = "Hack-to-select-VIDEOBUF2_DMA_CONTIG";
      patch = ../r39/0002-Hack-to-select-VIDEOBUF2_DMA_CONTIG.patch;
    }
    {
      # Required by the guide before building, not set in mainline's defconfig.
      name = "bring-your-own-kernel-config";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        ARM64_PMEM = yes;
      };
    }
    {
      name = "pstore";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        # conflicts with efi_pstore builtin default
        PSTORE_RAM = no;
      };
    }
  ] ++ kernelPatches;

  structuredExtraConfig = (import ../r39/common-config.nix { inherit lib; })
  // (import ../common-arch.nix { inherit lib; })
  // lib.optionalAttrs realtime (with lib.kernel; {
    PREEMPT_VOLUNTARY = lib.mkForce no;
    PREEMPT_RT = yes;
  }) // (with lib.kernel; {
    # nvidia-oot (configs/Makefile.config.nvmainline) builds its own spi-tegra210-quad;
    # drop the in-tree one so the module names don't collide.
    SPI_TEGRA210_QUAD = no;
  }) // structuredExtraConfig;
} // argsOverride)
