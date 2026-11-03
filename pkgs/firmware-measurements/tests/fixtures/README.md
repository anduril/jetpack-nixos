# Jetson fTPM PCR0 observations

The JP6 (36.5.2) and JP7 (39.2.1) fTPM-enabled OP-TEE HITL tests passed
on 2026-11-02 using an SBKPKC-fused Orin Nano devkit (flash variant
`3767-000-0005--1---`, capsule board specification
`3767-000-0005--1-0-jetson-orin-nano-devkit-`). Each capsule applied
successfully and switched the active bootloader slot from 0 to 1.

Each `pcr0-observed.json` contains the matching flash-initrd or capsule
SHA-256, the selected signed images' 64-byte BCH values, PCR0 events
in observed OP-TEE-then-EFI order, and live SHA-256, SHA-384 and SHA-512
PCR0 reads. The capsule capture also identifies its BUP by SHA-256.
The BCH values were extracted from signed images embedded in the exact
flasher initrd or selected BUP, not inferred from PCR predictions.
Replay extends only the banks present in each event; it agrees with
the live reads and separate artifact measurements for all four boots.

Raw firmware headers and TPM event logs remain outside the staged
fixture. Synthetic headers can test extraction offsets without
publishing signed firmware bytes.

The JP7 (39.2.1) `optee` HITL test passed on the SBKPKC
`thor-agx-devkit-fused0` on 2026-11-03, including a capsule update
that switched firmware slot 0 to 1. The device reported
`boot_security_info=0x228` and `security_mode=0`.
The initial flash variant was `3834-000-0008--1---`; the selected
capsule board specification was
`3834-000-0008--1-0-jetson-agx-thor-devkit-`. Its five signed images
are `MB2B`, `BL31`, `BL32`, `SECP` and `CPBL`. The initial BCH values
were extracted from the exact flasher initrd, and the capsule values
from the matched BUP. The flash initrd SHA-256 is
`09457aacf958c2b162805c5dee5b0df8389e40307b2b48beb9118fe41dad14b3`;
the capsule and BUP SHA-256 values are recorded in the post-capsule
fixture. Both boots have the same event order but different PCR0 values
across all three banks. Independent OP-TEE/EFI replay agrees with live
TPM reads, signed-image BCH digests and both artifact manifests.
