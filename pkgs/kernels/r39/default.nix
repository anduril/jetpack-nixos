{ lib
, applyPatches
, realtime ? false
, kernelPatches ? [ ]
, structuredExtraConfig ? { }
, argsOverride ? { }
, buildLinux
, gitRepos
, stdenv
, ...
}@args:
let
  common = import ./common-config.nix { inherit lib; };
in
buildLinux (args // {
  # See Makefile in kernel source root for VERSION/PATCHLEVEL/SUBLEVEL.
  version = "6.8.12";
  extraMeta.branch = "6.8";

  defconfig = "defconfig";

  # https://github.com/NixOS/nixpkgs/pull/366004
  # introduced a breaking change that if a module is declared but it is not being used it will fail
  # if you try to suppress each of he errors e.g.
  # REISERFS_FS_SECURITY = lib.mkForce unset; within structuredExtraConfig
  # that list runs to a long 100+ modules so we go back to the previous default and ignore them
  ignoreConfigErrors = true;

  # disabling the dependency on the common-config would seem appropriate as we define our own defconfig
  # however, it seems that some of the settings for e.g. fw loading are only made available there.
  # TODO: a future task could be to set this, disable ignoreConfigErrors and add the needed modules to the
  # structuredExtraConfig below.
  # enableCommonConfig = false;

  # Using applyPatches here since it's not obvious how to append an extra
  # postPatch. This is not very efficient.
  src = applyPatches {
    src = gitRepos."kernel/kernel-noble";
    postPatch = builtins.readFile ../fix-module-signing.sh;
  };
  autoModules = false;
  features = { }; # TODO: Why is this needed in nixpkgs master (but not NixOS 22.05)?

  extraMakeFlags = lib.optionals (lib.versionAtLeast stdenv.cc.version "16") [ "EXTRA_WARNINGS=-Wno-error=discarded-qualifiers" ];

  kernelPatches = common.kernelPatches ++ [
    {
      name = "usb: host: Export xhci_irq";
      patch = ./0001-usb-host-Export-xhci_irq.patch;
    }
  ] ++ kernelPatches;

  structuredExtraConfig = common.structuredExtraConfig
  // (import ../common-arch.nix { inherit lib; })
  // lib.optionalAttrs realtime (with lib.kernel; {
    PREEMPT_VOLUNTARY = lib.mkForce no; # Disable the one set in common-config.nix
    # These are the options enabled/disabled by source/generic_rt_build.sh (this file comes after source/source_sync.sh)
    PREEMPT_RT = yes;
    DEBUG_PREEMPT = no;
    KVM = no;
    EMBEDDED = yes;
    NAMESPACES = yes;
    CPU_IDLE_TEGRA18X = no;
    CPU_FREQ_GOV_INTERACTIVE = no;
    CPU_FREQ_TIMES = no;
    FAIR_GROUP_SCHED = no;
  }) // structuredExtraConfig;

} // argsOverride)
