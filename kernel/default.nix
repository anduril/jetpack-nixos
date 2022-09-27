# Due to some really weird behavior, we can't include "stdenv" in the function headedr or else the hackedSystem stuff below stops working.
{ pkgs, lib, stdenvNoCC, fetchFromGitHub, l4t-xusb-firmware, ... }@args:
let
  # overriding the platform to remove the USB_XHCI_TEGRA m which breaks the nvidia build
  hackedSystem = {
    system = "aarch64-linux";
    linux-kernel = {
      name = "aarch64-multiplatform";
      baseConfig = "defconfig";
      DTB = true;
      autoModules = true;
      preferBuiltin = true;
      extraConfig = ''
        # Raspberry Pi 3 stuff. Not needed for   s >= 4.10.
        ARCH_BCM2835 y
        BCM2835_MBOX y
        BCM2835_WDT y
        RASPBERRYPI_FIRMWARE y
        RASPBERRYPI_POWER y
        SERIAL_8250_BCM2835AUX y
        SERIAL_8250_EXTENDED y
        SERIAL_8250_SHARE_IRQ y

        # Cavium ThunderX stuff.
        PCI_HOST_THUNDER_ECAM y

        # Nvidia Tegra stuff.
        PCI_TEGRA y
      '';
      target = "Image";
    };
  };
  hackedPkgs = import pkgs.path {
    localSystem = if (stdenvNoCC.buildPlatform == stdenvNoCC.hostPlatform) then hackedSystem else stdenvNoCC.buildPlatform;
    ${if (stdenvNoCC.buildPlatform != stdenvNoCC.hostPlatform) then "crossSystem" else null} = hackedSystem;
  };
in hackedPkgs.buildLinux (args // rec {
  version = "5.10.104";
  extraMeta.branch = "5.10";

  defconfig = "tegra_defconfig";

  src = fetchFromGitHub {
    owner = "OE4T";
    repo = "linux-tegra-5.10";
    rev = "63c149056a7ef7bf146a747e7c8a179c1aaf72f7"; # 2022-08-18
    sha256 = "sha256-sIk3gxCuWHpFXjxqFIUGP1ApWsq7+fCC4nFB693Sdg0=";
  };
  autoModules = false;
  features = {}; # TODO: Why is this needed in nixpkgs master (but not NixOS 22.05)?

  structuredExtraConfig = with lib.kernel; {
    #  MODPOST modules-only.symvers
    #ERROR: modpost: "xhci_hc_died" [drivers/usb/host/xhci-tegra.ko] undefined!
    #ERROR: modpost: "xhci_hub_status_data" [drivers/usb/host/xhci-tegra.ko] undefined!
    #ERROR: modpost: "xhci_enable_usb3_lpm_timeout" [drivers/usb/host/xhci-tegra.ko] undefined!
    #ERROR: modpost: "xhci_hub_control" [drivers/usb/host/xhci-tegra.ko] undefined!
    #ERROR: modpost: "xhci_get_rhub" [drivers/usb/host/xhci-tegra.ko] undefined!
    #ERROR: modpost: "xhci_urb_enqueue" [drivers/usb/host/xhci-tegra.ko] undefined!
    #ERROR: modpost: "xhci_irq" [drivers/usb/host/xhci-tegra.ko] undefined!
    #USB_XHCI_TEGRA = module;
    USB_XHCI_TEGRA = yes;

    # stage-1 links /lib/firmware to the /nix/store path in the initramfs.
    # However, since it's builtin and not a module, that's too late, since
    # the kernel will have already tried loading!
    EXTRA_FIRMWARE_DIR = freeform "${l4t-xusb-firmware}/lib/firmware";
    EXTRA_FIRMWARE = freeform "nvidia/tegra194/xusb.bin";

    # Fix issue resulting in this error message:
    # FAILED unresolved symbol udp_sock
    #
    # https://lkml.iu.edu/hypermail/linux/kernel/2012.3/03853.html
    # https://lore.kernel.org/lkml/CAE1WUT75gu9G62Q9uAALGN6vLX=o7vZ9uhqtVWnbUV81DgmFPw@mail.gmail.com/
    # Could probably also be fixed by updating the GCC version used by default on ARM
    DEBUG_INFO_BTF = lib.mkForce no;

    # Override the default CMA_SIZE_MBYTES=32M setting in common-config.nix with the default from tegra_defconfig
    # Otherwise, nvidia's driver craps out
    CMA_SIZE_MBYTES = lib.mkForce (freeform "64");

    ### So nat.service and firewall work ###
    NF_TABLES = module; # This one should probably be in common-config.nix
    NFT_NAT = module;
    NFT_MASQ = module;
    NFT_REJECT = module;
    NFT_COMPAT = module;
    NFT_LOG = module;
    NFT_COUNTER = module;

    # Needed since mdadm stuff is currently unconditionally included in the initrd
    # This will hopefully get changed, see: https://github.com/NixOS/nixpkgs/pull/183314
    MD = yes;
    BLK_DEV_MD = module;
    MD_LINEAR = module;
    MD_RAID0 = module;
    MD_RAID1 = module;
    MD_RAID10 = module;
    MD_RAID456 = module;
  };

} // (args.argsOverride or {}))
