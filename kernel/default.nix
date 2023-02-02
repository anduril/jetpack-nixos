# Due to some really weird behavior, we can't include "stdenv" in the function headedr or else the hackedSystem stuff below stops working.
{ pkgs, lib, stdenvNoCC, fetchFromGitHub, l4t-xusb-firmware, realtime ? false, ... }@args:
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
  hackedPkgs = import pkgs.path (
    lib.optionalAttrs stdenvNoCC.buildPlatform.isAarch64 { localSystem = hackedSystem; }
    // lib.optionalAttrs (!stdenvNoCC.buildPlatform.isAarch64) { localSystem = stdenvNoCC.buildPlatform; crossSystem = hackedSystem; }
  );
in hackedPkgs.buildLinux (args // rec {
  version = "5.10.104" + lib.optionalString realtime "-rt63";
  extraMeta.branch = "5.10";

  defconfig = "tegra_defconfig";

  # Using applyPatches here since it's not obvious how to append an extra
  # postPatch. This is not very efficient.
  src = pkgs.applyPatches {
    src = fetchFromGitHub {
      owner = "OE4T";
      repo = "linux-tegra-5.10";
      rev = "5921377f5ffb5b1fbca9e40a187d1059743ef631"; # latest on oe4t-patches-l4t-r35.1 as of 2023-02-01
      sha256 = "sha256-3OvOk2Hlq1gsX34j2rwzJmlVt038ygDkepB4ysmbGxA=";
    };
    # Remove device tree overlays with some incorrect "remote-endpoint" nodes.
    # They are strings, but should be phandles. Otherwise, it fails to compile
    postPatch = ''
      rm \
        nvidia/platform/t19x/galen/kernel-dts/tegra194-p2822-camera-imx185-overlay.dts \
        nvidia/platform/t19x/galen/kernel-dts/tegra194-p2822-camera-dual-imx274-overlay.dts \
        nvidia/platform/t23x/concord/kernel-dts/tegra234-p3737-camera-imx185-overlay.dts \
        nvidia/platform/t23x/concord/kernel-dts/tegra234-p3737-camera-dual-imx274-overlay.dts

      sed -i -e '/imx185-overlay/d' -e '/imx274-overlay/d' \
        nvidia/platform/t19x/galen/kernel-dts/Makefile \
        nvidia/platform/t23x/concord/kernel-dts/Makefile

      '' + lib.optionalString realtime ''
      for p in $(find $PWD/rt-patches -name \*.patch -type f | sort); do
        echo "Applying $p"
        patch -s -p1 < $p
      done
    '';
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
  } // lib.optionalAttrs realtime {
    PREEMPT_VOLUNTARY = lib.mkForce no; # Disable the one set in common-config.nix
    # These are the options enabled/disabled by scripts/rt-patch.sh
    PREEMPT_RT = yes;
    DEBUG_PREEMPT = no;
    KVM = no;
    CPU_IDLE_TEGRA18X = no;
    CPU_FREQ_GOV_INTERACTIVE = no;
    CPU_FREQ_TIMES = no;
    FAIR_GROUP_SCHED = no;
  };

} // (args.argsOverride or {}))
