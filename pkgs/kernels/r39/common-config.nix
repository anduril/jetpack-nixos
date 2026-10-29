# Kernel patches and config shared by r39 and r39-mainline.
{ lib
, mainline ? false
}:
{
  kernelPatches = [
    {
      name = "Hack-to-select-VIDEOBUF2_DMA_CONTIG";
      patch = ./0002-Hack-to-select-VIDEOBUF2_DMA_CONTIG.patch;
      # drivers/media/platform/tegra/camera/vi/channel.c from
      # linux-oot-modules has ifdefs for
      # CONFIG_VIDEOBUF2_DMA_CONTIG, but actually requires it to
      # function.
      # Otherwise it hits a WARN_ON() and outputs
      # > tegra-capture-vi: failed to initialize VB2 queue
      structuredExtraConfig.VIDEOBUF2_DMA_CONTIG =
        if mainline then lib.kernel.module else lib.kernel.yes;
    }
  ];

  structuredExtraConfig = with lib.kernel; {
    # Override the default CMA_SIZE_MBYTES=32M setting in common-config.nix with the default from tegra_defconfig
    # Otherwise, nvidia's driver craps out
    CMA_SIZE_MBYTES = lib.mkForce (freeform "64");

    EROFS_FS = yes;
    # The baremetal initrd lists sdhci_pci; Tegra's defconfig lacks it.
    MMC_SDHCI_PCI = module;

    ### So nat.service and firewall work ###
    NF_TABLES = module;
    # this NFT_NAT is not actually being set. when build with enableCommonConfig = false;
    # and not ignoreConfigErrors = true; it will fail with error about unused option
    # unused means that it wanted to set it as a module, but make oldconfig didn't ask it about that option,
    # so it didn't get a chance to set it.
    NFT_NAT = module;
    NFT_MASQ = module;
    NFT_REJECT = module;
    NFT_COMPAT = module;
    NFT_LOG = module;
    NFT_COUNTER = option module;

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

    # Needed for booting from USB
    USB_UAS = module;

    FW_LOADER_COMPRESS_XZ = yes;
    FW_LOADER_COMPRESS_ZSTD = yes;

    # Restore default LSM from security/Kconfig. Undoes Nvidia downstream changes.
    LSM = freeform "landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,smack,tomoyo,apparmor,bpf";
    ### Already enabled by NVIDIA's defconfig (kernel-noble) ###

    # Block / device-mapper
    BLK_DEV_DM = yes; # DM_CRYPT/DM_VERITY below can only be =y if the core is built in
    CRYPTO_ESSIV = yes;
    DM_CRYPT = yes;
    DM_VERITY = yes;
    DM_MULTIPATH = module;

    # Filesystems
    EXFAT_FS = yes;
    EXT2_FS = yes;
    EXT2_FS_XATTR = yes;
    EXT2_FS_POSIX_ACL = yes;
    EXT2_FS_SECURITY = yes;
    NFSD = module;
    NFSD_V3_ACL = yes;
    NFSD_V4 = yes;
    NFSD_V4_SECURITY_LABEL = yes;
    NFS_V2 = module;
    CIFS = module;
    CIFS_XATTR = yes;
    CIFS_POSIX = yes;
    CIFS_UPCALL = yes;
    CIFS_DFS_UPCALL = yes;
    CIFS_FSCACHE = yes;

    # Qdiscs / classifiers (tc)
    NET_SCH_CODEL = yes;
    NET_SCH_FQ = yes;
    NET_SCH_FQ_CODEL = yes;
    NET_SCH_HFSC = yes;
    NET_SCH_HTB = yes;
    NET_SCH_PIE = yes;
    NET_SCH_SFQ = yes;
    NET_SCH_TBF = yes;
    NET_CLS_U32 = yes;
    NET_CLS_FW = yes;
    CLS_U32_MARK = yes;
    CLS_U32_PERF = yes;

    # ipset
    IP_SET = module;
    IP_SET_BITMAP_IP = module;
    IP_SET_BITMAP_IPMAC = module;
    IP_SET_BITMAP_PORT = module;
    IP_SET_HASH_IP = module;
    IP_SET_HASH_IPMAC = module;
    IP_SET_HASH_IPMARK = module;
    IP_SET_HASH_IPPORT = module;
    IP_SET_HASH_IPPORTIP = module;
    IP_SET_HASH_IPPORTNET = module;
    IP_SET_HASH_MAC = module;
    IP_SET_HASH_NET = module;
    IP_SET_HASH_NETIFACE = module;
    IP_SET_HASH_NETNET = module;
    IP_SET_HASH_NETPORT = module;
    IP_SET_HASH_NETPORTNET = module;
    IP_SET_LIST_SET = module;
    NETFILTER_XT_SET = module;

    # Other networking
    PPP = yes;
    PPP_ASYNC = yes;
    PPP_FILTER = yes;
    PPP_MULTILINK = yes;
    VXLAN = module;
    DUMMY = module;
    NVME_TCP = module;
    NVME_TCP_TLS = yes;
    BT_RFCOMM = module;
    BT_RFCOMM_TTY = yes;
    BT_BNEP = module;
    BT_BNEP_MC_FILTER = yes;
    BT_BNEP_PROTO_FILTER = yes;

    # Input / audio
    UHID = module;
    SND_USB_AUDIO = module; # NVIDIA has =y, but SND is only a module in mainline
    SND_USB_AUDIO_MIDI_V2 = yes;
  };
}
