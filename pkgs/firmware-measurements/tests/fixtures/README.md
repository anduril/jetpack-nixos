# Orin Nano fused PCR0 observations

The JP6 (36.5.2) and JP7 (39.2.1) fTPM-enabled OP-TEE HITL tests passed
on 2026-11-02 using a fused Orin Nano devkit (flash variant
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
