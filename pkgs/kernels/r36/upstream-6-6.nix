{ applyPatches
, lib
, fetchFromGitHub
, realtime ? false
, kernelPatches ? [ ]
, structuredExtraConfig ? { }
, argsOverride ? { }
, buildLinux
, gitRepos
, fetchgit
, fetchpatch
, ...
}@args:
buildLinux (args // {
  # See Makefile in kernel source root for VERSION/PATCHLEVEL/SUBLEVEL.
  version = "6.6.129";
  extraMeta.branch = "6.6";

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
  #enableCommonConfig = false;

  # Using applyPatches here since it's not obvious how to append an extra
  # postPatch. This is not very efficient.
  src = applyPatches {
    src = fetchgit {
      url = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git";
      hash = "sha256-rOZADwRv5QRyWblxnxBb6BdGiKqu2QLkwZFzSk2Wk04=";
      rev = "4fc00fe35d46b4fc8dac2eb543a0e3d44bb15f47";
    };

    patches = [

      (fetchpatch {
        name = "memory: tegra: Add Tegra234 clients for RCE and VI";
        url = "https://github.com/torvalds/linux/commit/9def28f3b8634e4f1fa92a77ccb65fbd2d03af34.patch";
        hash = "sha256-WZwKGL0kPZ3SxwdW3oi7Z3Tc0BMuuOuL9/HlLzg73q8=";
      })

      (fetchpatch {
        name = "hwmon: (ina3221) Add support for channel summation disable";
        url = "https://github.com/torvalds/linux/commit/7b64906c98fe503338066b97d3ff2dad65debf2b.patch";
        hash = "sha256-SB2zipFoJQsOjuKUFV8W1PBi8J8qTgdZcuPI3lNvGuA=";
      })

      (fetchpatch {
        name = "cpufreq: tegra194: save CPU data to avoid repeated SMP calls";
        url = "https://github.com/torvalds/linux/commit/6b121b4cf7e1f598beecf592d6184126b46eca46.patch";
        hash = "sha256-/v73qEkT3nrdzMDQZCbSMeacLSgj5aZTwnhvM1lFd+w=";
      })

      (fetchpatch {
        name = "cpufreq: tegra194: use refclk delta based loop instead of udelay";
        url = "https://github.com/torvalds/linux/commit/a60a556788752a5696960ed11409a552b79e68e8.patch";
        hash = "sha256-ZvogH5F3dUGHVXcpqhxbDah1Llc13J7SOYVVbJpstTw=";
      })

      (fetchpatch {
        name = "cpufreq: tegra194: remove redundant AND with cpu_online_mask";
        url = "https://github.com/torvalds/linux/commit/c12f0d0ffade589599a43b0d0f0965579ca80f76.patch";
        hash = "sha256-iiW20hwMQS/B6F1I3O5KwMdIVYrdOwSPzKrB5juaxMY=";
      })

      (fetchpatch {
        name = "fbdev/simplefb: Support memory-region property";
        url = "https://github.com/torvalds/linux/commit/8ddfc01ace51c85a2333fb9a9cbea34d9f87885d.patch";
        hash = "sha256-rMk0BIjOsc21HFF6Wx4pngnldp/LB0ODbUFGRDjtsUw=";
      })

      (fetchpatch {
        name = "fbdev/simplefb: Add support for generic power-domains";
        url = "https://github.com/torvalds/linux/commit/92a511a568e44cf11681a2223cae4d576a1a515d.patch";
        hash = "sha256-GOo7OLQObixVEKguiEzp1xLMlqE0QMQVhx8ygwkNb9M=";
      })
    ];
  };
  autoModules = false;
  features = { }; # TODO: Why is this needed in nixpkgs master (but not NixOS 22.05)?

  kernelPatches = [
    # Upstream does not have Intel IPU driver.
    # {
    #   name = "ipu: Depend on x86";
    #   patch = ./0001-ipu-Depend-on-x86.patch;
    # }
  ] ++ kernelPatches;

  structuredExtraConfig = with lib.kernel; {
    # Override the default CMA_SIZE_MBYTES=32M setting in common-config.nix with the default from tegra_defconfig
    # Otherwise, nvidia's driver craps out
    CMA_SIZE_MBYTES = lib.mkForce (freeform "64");

    # Kernel 6.6 extra configs
    ARM64_PMEM = yes;
    PCIE_TEGRA194 = yes;
    PCIE_TEGRA194_HOST = yes;
    BLK_DEV_NVME = yes;
    NVME_CORE = yes;
    FB_SIMPLE = yes;
    USB_ONBOARD_HUB = no;
    ISO9660 = module;
    USB_UAS = yes;

    ### So nat.service and firewall work ###
    NF_TABLES = module; # This one should probably be in common-config.nix
    # this NFT_NAT is not actually being set. when build with enableCommonConfig = false;
    # and not ignoreConfigErrors = true; it will fail with error about unused option
    # unused means that it wanted to set it as a module, but make oldconfig didn't ask it about that option,
    # so it didn't get a chance to set it.
    NFT_NAT = module;
    NFT_MASQ = module;
    NFT_REJECT = module;
    NFT_COMPAT = module;
    NFT_LOG = module;
    NFT_COUNTER = module;

    # search for "ip46tables" in nixpkgs and find all the -m options.
    # Enable the corresponding Kconfigs
    # TODO: nixpkgs should turn these on themselves.
    NETFILTER_XT_MATCH_PKTTYPE = module;
    NETFILTER_XT_MATCH_COMMENT = module;
    NETFILTER_XT_MATCH_CONNTRACK = module;
    NETFILTER_XT_MATCH_LIMIT = module;
    NETFILTER_XT_MATCH_MARK = module;
    NETFILTER_XT_MATCH_MULTIPORT = module;

    IP_NF_MATCH_RPFILTER = module;

    # IPv6 is enabled by default and without some of these `firewall.service` will explode.
    IP6_NF_MATCH_AH = module;
    IP6_NF_MATCH_EUI64 = module;
    IP6_NF_MATCH_FRAG = module;
    IP6_NF_MATCH_OPTS = module;
    IP6_NF_MATCH_HL = module;
    IP6_NF_MATCH_IPV6HEADER = module;
    IP6_NF_MATCH_MH = module;
    IP6_NF_MATCH_RPFILTER = module;
    IP6_NF_MATCH_RT = module;
    IP6_NF_MATCH_SRH = module;

    # Needed since mdadm stuff is currently unconditionally included in the initrd
    # This will hopefully get changed, see: https://github.com/NixOS/nixpkgs/pull/183314
    MD_LINEAR = module;
    MD_RAID0 = module;
    MD_RAID1 = module;
    MD_RAID10 = module;
    MD_RAID456 = module;

    FW_LOADER_COMPRESS_XZ = yes;
    FW_LOADER_COMPRESS_ZSTD = yes;

    # Restore default LSM from security/Kconfig. Undoes Nvidia downstream changes.
    LSM = freeform "landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,smack,tomoyo,apparmor,bpf";
  } // lib.optionalAttrs realtime {
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
  } // structuredExtraConfig;

} // argsOverride)
