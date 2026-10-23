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
specifications, or `common-1`/`common-2` for common-only payloads; flash
variants use directory names.

PCR 0 predictions follow NVIDIA's `ftpm_gen_measurement_list.py` for Orin
(`t234`) and Thor (`t264`). They assume measured boot and the normal firmware
event sequence. SHA-256 and SHA-384 include UEFI's zero-valued separator;
SHA-512 does not. Other SoCs have `pcr0: null` and an explanatory `reason`.

Signing and encryption remain nondeterministic. Fetch matched artifact and
`pcr` outputs and verify `artifact.sha256`; equal derivation paths alone do
not establish matching contents.
