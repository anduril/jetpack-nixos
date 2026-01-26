# NixOS module for NVIDIA Jetson devices

This repository packages components from NVIDIA's [JetPack SDK](https://developer.nvidia.com/embedded/jetpack) for use with NixOS, including:
 * Platform firmware flashing scripts
 * Linux kernel from NVIDIA for JetPack which includes some open-source drivers like nvgpu
 * An [EDK2-based UEFI firmware](https://github.com/NVIDIA/edk2-nvidia)
 * ARM Trusted Firmware / OP-TEE
 * Additional packages for:
   - GPU computing: CUDA, CuDNN, TensorRT
   - Multimedia: hardware accelerated encoding/decoding with V4L2 and gstreamer plugins
   - Graphics: Wayland, GBM, EGL, Vulkan
   - Power/fan control: nvpmodel, nvfancontrol

This package supports JetPack 5, 6, and 7. It works with NVIDIA's developer kits supported by these versions only:

|       Device       | JetPack 5 | JetPack 6 | JetPack 7 |
| ------------------ | --------- | --------- | --------- |
| Jetson Thor AGX    |           |           |     ✓     |
| Jetson Orin AGX    |     ✓     |     ✓     |           |
| Jetson Orin NX     |     ✓     |     ✓     |           |
| Jetson Orin Nano   |     ✓     |     ✓     |           |
| Jetson Xavier AGX  |     ✓     |           |           |
| Jetson Xavier NX   |     ✓     |           |           |

The Jetson Nano, TX2, and TX1 devices are _not_ supported, since support for them was dropped upstream in JetPack 5.

__NOTE__: CUDA is not currently supported in JetPack 7 (Thor AGX) due to dependencies on upstream nixpkgs. CUDA 13 support will be added after the release of NixOS/nixpkgs 25.11.

## Getting started

### Flashing UEFI firmware
This step may be optional if your device already has recent-enough firmware which includes UEFI. (Post-JetPack 5. Only newly shipped Orin devices might have this)
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
$ nix build github:anduril/jetpack-nixos#iso_minimal # iso_minimal_jp5 for Xavier (or otherwise wanting to use JetPack 5)
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
Include the following in your `configuration.nix` before installing:
```nix
{
  imports = [
    (builtins.fetchTarball "https://github.com/anduril/jetpack-nixos/archive/master.tar.gz" + "/modules/default.nix")
  ];

  hardware.nvidia-jetpack.enable = true;
  hardware.nvidia-jetpack.som = "xavier-agx"; # Other options include orin-agx, xavier-nx, and xavier-nx-emmc
  hardware.nvidia-jetpack.carrierBoard = "devkit";

  # Enable GPU support - needed even for CUDA and containers
  hardware.graphics.enable = true;
}
```
#### If you prefer using flakes do this instead:
For your `flake.nix`, include the following:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    jetpack.url = "github:anduril/jetpack-nixos/master"; # Add this line
    jetpack.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = inputs@{ self, nixpkgs, jetpack, ... } : { # Add jetpack
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      modules = [./configuration.nix jetpack.nixosModules.default]; # Add jetpack.nixosModules.default
    };
  };
}
```
And include this in your conf, i.e. `configuration.nix`
```nix
{
  hardware.nvidia-jetpack.enable = true;
  hardware.nvidia-jetpack.som = "xavier-agx"; # Other options include orin-agx, xavier-nx, and xavier-nx-emmc
  hardware.nvidia-jetpack.carrierBoard = "devkit";

  # Enable GPU support - needed even for CUDA and containers
  hardware.graphics.enable = true;
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

### JetPack Versions
The major JetPack version may be changed by setting `hardware.nvidia-jetpack.majorVersion`.
It defaults to the latest version supported by the board (e.g. JetPack 6 for Orin and JetPack 5 for Xavier).
The "generic" som defaults to JetPack 6.

Note that the JetPack firmware of a given version is incompatible with the kernel and rootfs of
the other. You cannot run the JetPack 5 firmware with the JetPack 6 kernel (and vice versa). Be
certain when upgrading that you are able to update both simulatenously. 

If not installing JetPack 6 firmware via flashing scripts, it is recommended to install the
JetPack 6 bootloader configuration (without live switch), then install the capsule update,
and finally reboot. The effect is that the device reboots, installs the JetPack 6 firmware
via a capsule update, and when finished, boots into a NixOS configuration for JetPack 6.

### Graphical Output
As of 2023-12-09, the status of graphical output on Jetsons is described below.
If you have problems with configurations that are expected to work, try different ports (HDMI/DP/USB-C), different cables, and rebooting with the cables initially connected or disconnected.

For DP on Orin AGX in particular: try connecting the cable when the fan temporarily stops during the boot.

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
Recent versions of JetPack (>=5.1) support updating the device firmware from the device using the UEFI Capsule update mechanism.
This can be done as a more convenient alternative to physically attaching to the device and re-running the flash script.
These updates can be performed automatically after a `nixos-rebuild switch` if the `hardware.nvidia-jetpack.bootloader.autoUpdate` setting is set to true.
Otherwise, the instructions to apply the update manually are below.

To determine if the currently running firmware matches the software, run, `ota-check-firmware`:
```
$ ota-check-firmware
Current firmware version is: 35.6.1-06cb4270ebfe
Expected firmware version is: 35.6.1-06cb4270ebfe
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
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation = {
    docker.enable = true;
    podman.enable = true;
  };
}
```

Note that on newer nixpkgs the `virtualisation.{docker,podman}.enableNvidia` option is deprecated in favor of using `hardware.nvidia-container-toolkit.enable` instead.

To run a container with access to nvidia hardware, you must specify a device to
passthrough to the container in the [CDI](https://github.com/cncf-tags/container-device-interface/blob/main/SPEC.md#overview)
format. By default, there will be a single device setup of the kind
"nvidia.com/gpu" named "all". To use this device, pass
`--device=nvidia.com/gpu=all` when starting your container.

If you are using Podman, it is recommended to add a dependency to any systemd services that run podman to specify `After=nvidia-container-toolkit-cdi-generator.service`. Due to Podman's daemonless nature, this ensures that the CDI configuration files are generated prior to container start.

### Using the kernel package sets

There are two predefined kernel package sets in the overlay. They use sources
from Jetson Linux.

- `pkgs.nvidia-jetpack.kernelPackages`
- `pkgs.nvidia-jetpack.rtkernelPackages`

The NixOS module uses these sets by default.

On JetPack 6+, however, you may use a mainline package set instead.
Consult the [Bring Your Own Kernel](https://docs.nvidia.com/jetson/archives/r36.4.4/DeveloperGuide/SD/Kernel/BringYourOwnKernel.html) documentation for more details.

When using a custom package set in the NixOS configuration, the out-of-tree
modules must be added using the provided overlay.

e.g. (using the `pkgs.nvidia-jetpack.kernelPackages` set)

```nix
{ pkgs, ... }:

{
  config.boot.kernelPackages = pkgs.nvidia-jetpack.kernelPackages.extend pkgs.nvidia-jetpack.kernelPackagesOverlay
}
```

## Configuring CUDA for Nixpkgs

> [!NOTE]
>
> Nixpkgs as created by NixOS configurations using JetPack NixOS modules is automatically configured to enable CUDA support for Jetson devices.
> This behavior can be disabled by setting `hardware.nvidia-jetpack.configureCuda` to `false`, in which case Nixpkgs should be configured as described in [Importing Nixpkgs](#importing-nixpkgs).

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
