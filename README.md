# NixOS module for NVIDIA Jetson devices

This repository packages components from NVIDIA's [Jetpack SDK](https://developer.nvidia.com/embedded/jetpack) for use with NixOS, including:
 * Platform firmware flashing scripts
 * A 5.10 Linux kernel from NVIDIA, which includes some open-source drivers like nvgpu
 * An [EDK2-based UEFI firmware](https://github.com/NVIDIA/edk2-nvidia)
 * ARM Trusted Firmware / OP-TEE
 * Additional packages for:
   - GPU computing: CUDA, CuDNN, TensorRT
   - Multimedia: hardware accelerated encoding/decoding with V4L2 and gstreamer plugins
   - Graphics: Wayland, GBM, EGL, Vulkan
   - Power/fan control: nvpmodel, nvfancontrol

This package is based on the Jetpack 5 release, and will only work with devices supported by Jetpack 5.1:
 * Jetson Orin AGX
 * Jetson Orin NX
 * Jetson Xavier AGX
 * Jetson Xavier NX

The Jetson Nano, TX2, and TX1 devices are _not_ supported, since support for them was dropped upstream in Jetpack 5.
In the future, when the Orin Nano is released, it should be possible to make it work as well.

## Getting started

### Flashing UEFI firmware
This step may be optional if your device already has recent-enough firmware which includes UEFI. (Post-Jetpack 5. Only newly shipped Orin devices might have this)
If you are unsure, I'd recommend flashing the firmware anyway.

Plug in your Jetson device, press the "power" button" and ensure the power light turns on.
Then, to enter recovery mode, hold the "recovery" button down while pressing the "reset" button.
Connect via USB and verify the device is in recovery mode.
```shell
$ lsusb | grep -i NVIDIA
Bus 003 Device 013: ID 0955:7023 NVIDIA Corp. APX
```

On an x86_64 machine (some of NVIDIA's precompiled components like `tegrarcm_v2` are only built for x86_64),
build and run (as root) the flashing script which corresponds to your device (making sure to
replace `xavier-agx` with the name of your device, use `nix flake show` to see options):

```shell
$ nix build github:anduril/jetpack-nixos#flash-xavier-agx-devkit
$ sudo ./result/bin/flash-xavier-agx-devkit
```

At this point, your device should have a working UEFI firmware accessible either a monitor/keyboard, or via UART.

### Installation ISO

Now, build and write the customized installer ISO to a USB drive:
```shell
$ nix build github:anduril/jetpack-nixos#iso_minimal
$ sudo dd if=./result/iso/nixos-22.11pre-git-aarch64-linux.iso of=/dev/sdX bs=1M oflag=sync status=progress
```
(Replace `/dev/sdX` with the correct path for your USB drive)

As an alternative, you could also try the generic ARM64 multiplatform ISO from NixOS. See https://nixos.wiki/wiki/NixOS_on_ARM/UEFI
(Last I tried, this worked on Xavier AGX but not Orin AGX. We should do additional testing to see exactly what is working or not with the vendor kernel vs. mainline kernel)

### Installing NixOS

Insert the USB drive into the Jetson device.
On the AGX devkits, I've had the best luck plugging into the USB-C slot above the power barrel jack.
You may need to try a few USB options until you find one that works with both the UEFI firmware and the Linux kernel.

Press power / reset as needed.
When prompted, press ESC to enter the UEFI firmware menu.
In the "Boot Manager", select the correct USB device and boot directly into it.

Follow the [NixOS manual](https://nixos.org/manual/nixos/stable/index.html#sec-installation) for installation instructions, using the instructions specific to UEFI devices.
Include the following in your `configuration.nix` (or the equivalent in your `flake.nix`) before installing:
```nix
{
  imports = [
    (builtins.fetchTarball "https://github.com/anduril/jetpack-nixos/archive/master.tar.gz" + "/modules/default.nix")
  ];

  hardware.nvidia-jetpack.enable = true;
  hardware.nvidia-jetpack.som = "xavier-agx"; # Other options include orin-agx, xavier-nx, and xavier-nx-emmc
  hardware.nvidia-jetpack.carrierBoard = "devkit";
}
```
The Xavier AGX contains some critical firmware paritions on the eMMC.
If you are installing NixOS to the eMMC, be sure to not remove these partitions!
You can remove and replace the "UDA" partition if you want to install NixOS to the eMMC.
Better yet, install to an SSD.

After installing, reboot and pray!

##### Xavier AGX note:
On all recent Jetson devices besides the Xavier AGX, the firmware stores the UEFI variables on a flash chip on the QSPI bus.
However, the Xavier AGX stores it on a `uefi_variables` partition on the eMMC.
This means that it cannot support runtime UEFI variables, since the UEFI runtime drivers to access the eMMC would conflict with the Linux kernel's drivers for the eMMC.
Concretely, that means that you cannot modify the EFI variables from Linux, so UEFI bootloaders will not be able to create an EFI boot entry and reorder the boot options.
You may need to enter the firmware menu and reorder it manually so NixOS will boot first.
(See [this issue](https://forums.developer.nvidia.com/t/using-uefi-runtime-variables-on-xavier-agx/227970))

### Graphical Output
As of 2023-12-09, the status of graphical output on Jetsons is described below.
If you have problems with configurations that are expected to work, try different ports (HDMI/DP/USB-C), different cables, and rebooting with the cables initially connected or disconnected.

#### Linux Console
On Orin AGX/NX/Nano, the Linux console does not seem to work at all on the HDMI/DisplayPort.
This may be an upstream limitation (not jetpack-nixos specific).

On Xavier AGX and Xavier NX, add `boot.kernelParams = [ "fbcon=map:<n>" ]`, replacing `<n>` with the an integer according to the following:

Xavier AGX devkit:
- 0 for front USB-C port (recovery port)
- 1 for rear USB-C port (above power barrel jack)
- 2 for rear HDMI port

Xavier NX devkit:
- 0 for DisplayPort
- 1 for HDMI

Given the unreliability of graphical console output on Jetson devices, I recommend using the serial port as the go-to for troubleshooting.

#### X11
Set `hardware.nvidia-jetpack.modesetting.enable = false;`.
This is currently the default, but the default may change in the future.
LightDM+i3 and LightDM+Gnome have been tested working. (Remember to add the user to the "video" group)
GDM apparently does not currently work.

#### Wayland
Set `hardware.nvidia-jetpack.modesetting.enable = true;`
Weston and sway have been tested working on Orin devices, but do not work on Xavier devices.

### Updating firmware from device
Recent versions of Jetpack (>=5.1) support updating the device firmware from the device using the UEFI Capsule update mechanism.
This can be done as a more convenient alternative to physically attaching to the device and re-running the flash script.
These updates can be performed automatically after a `nixos-rebuild switch` if the `hardware.nvidia-jetpack.bootloader.autoUpdate` setting is set to true.
Otherwise, the instructions to apply the update manually are below.

To determine if the currently running firmware matches the software, run, `ota-check-firmware`:
```
$ ota-check-firmware
Current firmware version is: 35.6.1
Current software version is: 35.6.1
```

If these versions do not match, you can update your firmware using the UEFI Capsule update mechanism. The procedure to do so is below:

To build a capsule update file, build the
`config.system.build.uefiCapsuleUpdate` attribute from your NixOS build. For the standard devkit configurations supported in this repository, one could also run (for example),
`nix build .#uefi-capsule-update-xavier-nx-emmc-devkit`. This will produce a file that you can scp (no need for `nix copy`) to the device to update.

Once the file is on the device, run:
```
$ sudo ota-apply-capsule-update example.Cap
$ sudo reboot
```
(Assuming `example.Cap` is the file you copied to the device.) While the device is rebooting, do not disconnect power.  You should be able to see a progress bar while the update is being applied. The capsule update works by updating the non-current slot A/B firmware partitions, and then rebooting into the new slot. So, if the new firmware does not boot up to UEFI, it should theoretically rollback to the original firmware.

After rebooting, you can run `ota-check-firmware` to see if the firmware version had changed.
Additionally, you can get more detailed information on the status of the firmware update by running:
```
$ sudo nvbootctrl dump-slots-info
```
The Capsule update status is one of the following integers:
- 0 - No Capsule update
- 1 - Capsule update successfully
- 2 - Capsule install successfully but boot new firmware failed
- 3 - Capsule install failed

### UEFI Capsule Authentication

To ensure only authenticated capsule updates are applied to the device, you can
build the UEFI firmware and each subsequent capsule update using your own signing keys.
An overview of the key generation can be found at [EDK2 Capsule Signing](https://github.com/tianocore/tianocore.github.io/wiki/Capsule-Based-System-Firmware-Update-Generate-Keys).

To include your own signing keys in the EDK2 build and capsule update, make
sure the option `hardware.nvidia-jetpack.firmware.uefi.capsuleAuthentication.enable`
is turned on and each signing key option is set.

### OCI Container Support

You can run OCI containers with jetpack-nixos by enabling the following nixos options:

```nix
{
  virtualisation.podman.enable = true;
  virtualisation.podman.enableNvidia = true;
}
```

Note that on newer nixpkgs the `virtualisation.{docker,podman}.enableNvidia` option is deprecated in favor of using `hardware.nvidia-container-toolkit.enable` instead. This new option does not work yet with Jetson devices, see [this issue](https://github.com/nixos/nixpkgs/issues/344729).

To run a container with access to nvidia hardware, you must specify a device to
passthrough to the container in the [CDI](https://github.com/cncf-tags/container-device-interface/blob/main/SPEC.md#overview)
format. By default, there will be a single device setup of the kind
"nvidia.com/gpu" named "all". To use this device, pass
`--device=nvidia.com/gpu=all` when starting your container. If you need to
configure more CDI devices on the NixOS host, just note that the path
/var/run/cdi/jetpack-nixos.yaml will be taken by jetpack-nixos.

As of December 2023, Docker does not have a released version that supports the
CDI specification, so Podman is recommended for running containers on Jetson
devices. Docker is set to get experimental CDI support in their version 25
release.

## Configuring CUDA for Nixpkgs

### Importing Nixpkgs

To configure Nixpkgs to advertise CUDA support, ensure it is imported with a config similar to the following:

```nix
{
  config = {
    allowUnfree = true;
    cudaSupport = true;
    cudaCapabilities = [ "7.2" "8.7" ];
  };
}
```

> [!IMPORTANT]
>
> The `config` attribute set is not part of Nixpkgs' fixed-point, so re-evaluation only occurs through use of `pkgs.extend`.
> It is imperative that Nixpkgs is properly configured during import.

Breaking down these components:

- `allowUnfree`: CUDA binaries have an unfree license
- `cudaSupport`: Packages in Nixpkgs enabled CUDA acceleration based on this value
- `cudaCapabilities`: [Specific CUDA architectures](https://developer.nvidia.com/cuda-gpus) for which CUDA-accelerated packages should generate device code

> [!IMPORTANT]
>
> While supplying `config.cudaCapabilities` is optional for x86 and SBSA systems, it is mandatory for Jetsons, as Jetson capabilities are not included in the defaults.
>
> Furthermore, it is strongly recommended that `config.cudaCapabilities` is always set explicitly, given it reduces build times, produces smaller closures, and provides the CUDA compiler more opportunities for optimization.

So, the above configuration allows building CUDA-accelerated packages (through `allowUnfree` and `cudaSupport`) and tells Nixpkgs to generate device code targeting Xavier (`"7.2"`) and Orin (`"8.7"`).

### Re-using `jetpack-nixos`'s CUDA package set

While our overlay exposes a CUDA package set through `pkgs.nvidia-jetpack.cudaPackages`, packages like OpenCV and PyTorch don't know to look there.
Worse yet, even if we overrode the CUDA package sets they recieved, we would need to do the same for all their transitive dependencies!

To make `jetpack-nixos`'s CUDA package set the default, provide Nixpkgs with this overlay:

```nix
final: _: { inherit (final.nvidia-jetpack) cudaPackages; }
```

## Additional Links

Much of this is inspired by the great work done by [OpenEmbedded for Tegra](https://github.com/OE4T).
We also use the cleaned-up vendor kernel from OE4T.
