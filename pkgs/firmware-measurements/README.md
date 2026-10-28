# Firmware Measurements

`system.build.initrdFlashScript.pcr` and `system.build.uefiCapsuleUpdate.pcr`
contain `measurements.json`, produced by the same derivation as the artifact.

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
