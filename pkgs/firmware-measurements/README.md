# Firmware Measurements

`system.build.initrdFlashScript.pcr` and `system.build.uefiCapsuleUpdate.pcr`
contain `measurements.json`, produced by the same derivation as the artifact.

The standalone tool requires Python 3.11 or later and `pyzstd`.
The Nix package provides both.

The JSON includes:

- `artifact.type` and `artifact.file`: artifact type and file basename.
- `artifact.sha256`: hash of the file listed below.
- `artifact.bupSha256`: BUP hash for supported capsules.
- `pcr0.variants.<variant>.{sha256,sha384,sha512}`: predicted PCR 0.
- `pcr0.variants.<variant>.events`: ordered firmware and separator events with
  their per-bank digests.

| Artifact | File hashed by `artifact.sha256` |
| --- | --- |
| Single-variant flasher | `out/libexec/rcm/bootloader/boot.img` |
| Multi-variant flasher | `out/libexec/initrd` |
| Capsule | The capsule file at `out` |

The flasher measures persisted firmware inside its bundled recovery initrd,
not the temporary RCM firmware. Its JSON is also available at
`out/share/jetpack/measurements.json`. Capsule measurements use the same BUP
snapshot passed to capsule encoding. Capsule variants use BUP board
specifications, matching empty fields as wildcards in BUP entry order.
Common-only payloads use `common-1`/`common-2` only for fuse modes with an
applicable entry for every image. Flash variants use directory names.

PCR 0 predictions follow NVIDIA's `ftpm_gen_measurement_list.py` for Orin
(`t234`) and Thor (`t264`). They assume measured boot and the normal firmware
event sequence. SHA-256 and SHA-384 include UEFI's zero-valued separator;
SHA-512 does not. Other SoCs have `pcr0: null` and an explanatory `reason`.

Signing and encryption remain nondeterministic. Fetch matched artifact and
`pcr` outputs and verify `artifact.sha256`; equal derivation paths alone do
not establish matching contents.

## Measurement Model

The header offsets, event order and bank-specific digest handling come from
NVIDIA's `optee/samples/ftpm-helper/host/tool/ftpm_gen_measurement_list.py`:

- [L4T 36.5.2, revision c042ac75](https://gitlab.com/nvidia/nv-tegra/tegra/optee-src/nv-optee/-/blob/c042ac75cbf86b7b953757f6e9ff57ccbd49c820/optee/samples/ftpm-helper/host/tool/ftpm_gen_measurement_list.py)
  covers Orin.
- [L4T 39.2.1, revision 56d6543d](https://gitlab.com/nvidia/nv-tegra/tegra/optee-src/nv-optee/-/blob/56d6543d646fa22c6524f032bbd66c7f4c74ac05/optee/samples/ftpm-helper/host/tool/ftpm_gen_measurement_list.py)
  covers Orin and Thor.

Both helpers read the 64-byte BCH digest at offset `0x1460`. For each firmware
event, SHA-512 uses that digest directly. SHA-256 and SHA-384 hash those
64 bytes first. Both helpers append the zero-valued separator only for
SHA-256 and SHA-384.

The pinned UEFI sources use `PcdTpm2HashMask = 0x00000006` and
`PcdTcg2HashAlgorithmBitmap = 0x00000006`, and link only SHA-256 and SHA-384
hash instances into `Tcg2Dxe`:

- [EDK2 NVIDIA r36.5.1](https://github.com/NVIDIA/edk2-nvidia/blob/r36.5.1/Platform/NVIDIA/NVIDIA.common.dsc.inc#L1110)
  is the UEFI source used with L4T 36.5.2.
- [EDK2 NVIDIA r39.2.1](https://github.com/NVIDIA/edk2-nvidia/blob/r39.2.1/Platform/NVIDIA/NVIDIA.common.dsc.inc#L1158)
  is the UEFI source used with L4T 39.2.1.

SHA-512 separator omission is specific to this NVIDIA UEFI configuration.
It is not a general EDK2 rule. Custom UEFI patches that change hash masks,
hash instances or PCR0 events require a matching prediction model.
Source agreement does not replace validation against the exact flashed
headers, complete event logs and live PCR values.

## Recovery Payload Verification

The recovery initrd must contain one gzip-compressed, Zstandard-compressed
or uncompressed newc CPIO archive. The flash-initrd module uses the NixOS
default compressor and accepts `gzip`, `zstd` and `cat`. It rejects other
compressors and prepended archives. The parser supports streaming and
multi-frame Zstandard input. It allows zero padding after the decompressed
CPIO trailer but rejects concatenated archives and other trailing data.

Before RCM starts, the flasher checks `share/jetpack/flash-payload.sha256`.
For a single-variant flasher, this check covers only the bundled `boot.img`.
For a multi-variant flasher, it covers only the bundled initrd. It does not
verify the complete RCM tool tree or signed/encrypted derivatives sent by
RCM. The PCR0 predictions describe persisted firmware, not temporary RCM
firmware. A checksum mismatch stops the flasher and prints an error.

## Capsule Migration

Adding the `pcr` output changes every `uefiCapsuleUpdate` derivation and
output store path, including configurations that sign capsules.
Downstream signing pipelines and caches must refresh their capsule
references. Fetch the final capsule and its `pcr` output together and
verify `artifact.sha256` before using the predictions. Do not pair an old
capsule with measurements from the new derivation.

## PCRs Not Included

This tool does not predict PCRs 1, 2 or 3 or publish their event lists.
UEFI can still extend these PCRs during boot. NVIDIA's
`ftpm_gen_measurement_list.py` generates PCR 0 only and excludes UEFI
measurements for PCRs 1 through 8 and PCR 12.

- PCR 1 contains platform configuration. EDK2 measures `BootOrder` and the
  referenced `Boot####` variables into this PCR. These measurements can
  detect changes to boot entries and their order. Entries can contain
  device-specific data, such as MAC addresses and storage device paths.
  The signed firmware images do not determine these variables. A common
  expected PCR value requires control of the boot variables on each device.
- PCR 2 contains external firmware code, such as EFI drivers and option
  ROMs. EDK2 measures loaded EFI boot-service and runtime drivers into this
  PCR. These measurements can identify external code when it is loaded.
  The saved Orin EFI event log contains only a separator event for PCR 2.
  The flash and capsule artifacts do not determine which external drivers
  or option ROMs a device loads.
- PCR 3 contains external firmware configuration, such as data for
  pluggable hardware. The saved Orin EFI event log contains only a
  separator event for PCR 3. It contains no external configuration
  measurement to predict from the flash or capsule artifacts.

A separator event alone identifies no firmware image or configuration.
The Orin observations do not establish the event sequences for all devices
or for Thor. Before you use these PCRs in a policy, check the complete EFI
event log and verify that its replay matches the live PCR values.
