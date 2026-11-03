# PCR0 Review Plan

Review: [jetpack-nixos PR 583](https://github.com/anduril/jetpack-nixos/pull/583).

The review contains 12 inline comments and one SBK-encryption question.
The unit test repeats the production model. The downstream hardware helper
checks event digests across banks but replays only SHA-256.

## Feedback Items

1. **Add golden fixtures.** Status: complete for the agreed hardware matrix.
   [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169299).
   Capture real signed-header excerpts, separate OP-TEE and EFI logs, observed
   PCR0 values and capture metadata. Keep raw firmware and logs untracked;
   commit only sanitized BCH values, event digests and live PCR reads.
   Orin Nano JP6/JP7 and fused Thor JP7 captures cover initial flash and
   post-capsule boots. Expected values and event order come from fixtures,
   not production constants. Other board and key combinations remain outside
   the agreed fixture matrix.

   **Fixture acquisition:**
   - For each flashed configuration, build the exact flasher used on the
     device and both outputs in one invocation:
     `nix build --no-link --print-out-paths "<flake>#nixosConfigurations.<systemName>.config.system.build.initrdFlashScript^*"`.
     Save the printed `out` and `pcr` paths, the flasher derivation, device
     identity, board specification, fuse mode, L4T/UEFI revisions and flash
     date. Keep `out/share/jetpack/measurements.json` (or
     `pcr/measurements.json`) and `out/share/jetpack/flash-payload.sha256`.
     Verify `artifact.sha256` against the file named in
     `pkgs/firmware-measurements/README.md` before using its predictions.
     Do not mix outputs from separately signed builds.
   - Extract persisted images from that flasher's `out/libexec/initrd`, or
     from the ramdisk inside `out/libexec/rcm/bootloader/boot.img` for a
     single-variant flasher. Decompress the gzip/Zstandard initrd as needed
     and unpack its newc CPIO archive. Use the embedded signed-firmware
     store path (`flashInitrd.passthru.signedFirmware`) as the archive prefix;
     select the flashed variant's files, not the temporary RCM firmware.
     Check `flash.idx` and retain the image filenames and SHA-256 hashes.
     For Orin identify `MB2B`, `TOSB`, `CPBL`; for Thor identify `MB2B`,
     `BL31`, `BL32`, `SECP`, `CPBL` by the magic at offset `0x1400`.
     Save each image's first `0x14a0` bytes as its signed-header excerpt;
     the measured 64-byte BCH digest is at `0x1460:0x14a0`. Compare those
     bytes with the corresponding OP-TEE SHA-512 event digest before
     calling the headers matched.
   - For a capsule run, build both
     `"<flake>#nixosConfigurations.<systemName>.config.system.build.uefiCapsuleUpdate^*"`
     outputs together. Retain the capsule hash, `pcr/measurements.json` and
     the exact `pkgs.nvidia-jetpack.bup/bl_only_payload` input used to
     generate it. Extract the selected board/fuse-mode BUP entries' signed
     headers, not headers from a different signed-firmware build.
   - On the booted device, save `tpm2_pcrread` for SHA-256, SHA-384 and
     SHA-512 PCR0, the EFI binary log at
     `/sys/kernel/security/tpm0/binary_bios_measurements`, and the separate
     OP-TEE binary log from `optee-eventlog-dump`. Decode each with
     `tpm2_eventlog`; preserve the binaries and record which device boot and
     flash/capsule artifact they belong to. The downstream collection
     commands are in `hitl-device-tests/optee.nix` in the
     `user/jhoffer/jetpack_ftpm` anduril-nixpkgs worktree. The existing
     `/tmp/optee-pcr7-artifacts.XohIvw` is a historical capture, not a
     golden fixture: its OP-TEE replay is only a partial-log PCR0. The
     matched JP6/JP7 captures below supersede it.
   - Retain matched raw captures outside Git; commit compact BCH values,
     event digests, observed PCR0 values and artifact hashes. Derive expectations by
     replaying the recorded events and compare all advertised banks against
     the live reads and matched image digests; do not copy the production
     event order or predicted PCR values into the expected data.

   The JP6 and JP7 `jetpackUefiCapsuleUpdate` tests passed on
   `orin-nano-devkit-fused0` on 2026-11-02, but their non-fTPM
   artifact-only captures are not golden PCR0 fixtures. The revised
   fTPM-enabled `optee` HITL tests also passed on the same board for
   both releases, including successful capsule updates. The
   `orin-nano-fused-jp6-ftpm` and `orin-nano-fused-jp7-ftpm` directories
   under `pkgs/firmware-measurements/tests/fixtures/` contain initial
   and post-capsule raw OP-TEE/EFI logs, live PCR reads, matched flash
   and BUP headers, measurement manifests and provenance. For each
   of the four boots, combined-log replay, manifest prediction and
   live PCR0 agree in SHA-256, SHA-384 and SHA-512; every selected
   signed-header BCH digest matches its firmware event. Flash headers
   must be extracted from the images embedded in the exact flasher
   initrd, not the current signed-firmware store path. The JP7 Thor
   `optee` test also passed on SBKPKC `thor-agx-devkit-fused0` on
   2026-11-03, including a capsule update; its five matched header
   digests and all three live PCR0 banks agree for the initial and
   post-update boots. The fused boot has different PCR0 values from
   the unfused Thor capture. Raw Thor logs remain untracked.

2. **Document the measurement model.** Status: complete.
   [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169306).
   Cite the pinned NVIDIA helper revisions and UEFI configuration.
   The `r36.5.1` and `r39.2.1` UEFI sources set both hash masks to `0x6`
   and link SHA-256/SHA-384 hash instances. Explain that SHA-512 separator
   omission is configuration-specific, not general EDK2 behavior.
   Verify raw BCH-digest handling against matched headers and hardware logs.
   Completed: pinned helper and UEFI citations, raw-digest explanation and
   configuration-specific separator documentation. Matched Orin and Thor
   headers, event logs and live PCR0 reads validate the covered builds.

3. **Fix signed-firmware provenance.** Status: complete.
   [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169314).
   Expose embedded `signedFirmware` through `flashInitrd.passthru` and use
   that value as the archive lookup key. Remove the independently supplied
   argument. Add an override regression test proving measurements follow
   embedded firmware without adding another runtime dependency.
   Completed: passthrough wiring and regression checks for both flasher modes.

4. **Enforce the initrd format.** Status: complete.
   [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169321).
   Keep the NixOS default compressor and support gzip, Zstandard and raw
   initrds. Reject unsupported compression
   and nonpadding data after the first CPIO trailer with specific errors.
   Test raw/gzip/Zstandard archives, valid padding, concatenated archives,
   unsupported compression and truncation.
   Completed: NixOS default compressor, compressor/prepend assertions,
   trailer validation and parser regression tests, including gzip/Zstandard
   checksum verification and streaming/multi-frame Zstandard input.

5. **Expand payload verification.** Status: partial.
   [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169329).
   Hash the complete prepared RCM tree, including `flashcmd.txt`, scripts
   and signed/encrypted derivatives. Keep PCR prediction scoped to persisted
   firmware. Print an error before exiting on mismatch, and test that
   tampering prevents RCM execution. Document the narrower scope of
   dynamically generated multi-variant RCM files.
   Completed: explicit checksum failure reporting, fail-before-RCM regression
   checks and documentation of the current verification scope. The
   prebuilt single-variant RCM tree is now checked before execution,
   including `flashcmd.txt`, signed images and added files.
   The multi-variant flasher now verifies its bundled NVIDIA flash-tools
   file list and hashes before running the flash script. A real Orin Nano
   JP7 multi-variant flasher built, and both bundled payload manifests
   passed checksum verification. Regression checks reject changed, missing
   and extra tool files before RCM execution. Board-specific `flashcmd.txt`
   and signed/encrypted RCM images generated afterward remain unchecked.
   Closing that gap requires prebuilding all supported variants and
   independently selecting the expected tree for the board. A real Thor
   single-variant build passed both the flash-image checksum and the
   complete RCM file-list/content comparison; its RCM tree has no directory
   symlinks. Regression checks reject changed, missing and extra RCM files
   before RCM execution.

6. **Separate heavy payload construction.** Status: complete.
   [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169334).
   Move copying, measurement generation and manifests into a
   cache-substitutable payload derivation. Keep the shell wrapper small and
   preserve the public `.pcr` accessor. Compare `nix path-info -rS` before and
   after. Check for retained duplicate payloads and unnecessary kernel or
   firmware references.
   Payload copying, checksums and PCR measurements are in a separate
   derivation. The wrapper retains `out/libexec`, `out/share` and `.pcr`.
   Real Orin Nano JP7 and Thor T4000 flashers built with both outputs;
   checksums and `.pcr` contents agree. Each wrapper references one
   payload derivation rather than a copied payload. The Orin wrapper still
   references kernel and flash tools required for dynamic RCM generation;
   the Thor wrapper does not directly retain a kernel or firmware path.
   Against the same configurations at commit `1076930`, `nix path-info -S`
   reports 2,806,879,416 to 2,806,880,224 bytes for Orin and
   1,410,503,760 to 1,412,565,656 bytes for Thor. Separation improves
   caching, not closure size; the Thor RCM checksum manifest adds overhead.

7. **Document capsule path changes.** Status: complete.
   [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169343).
   Add a downstream migration note explaining that the additional output
   changes capsule derivation and output paths. Signing pipelines must
   refresh references and fetch matched capsule/measurement outputs rather
   than reuse old cached paths.
   Completed: downstream signing and cache migration documentation.

8. **Make variants comparable.** Status: partial.
   [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169351).
   Preserve existing keys and add explicit board-spec and fuse-mode metadata.
   Represent common-only targets without inventing a board identity.
   Add a PKC-only flash-versus-capsule cross-check for matched targets.
   Compare header digests, events and all three PCR0 values.
   Completed: board-spec and fuse-mode metadata in the measurement
   output, null board identity for common-only targets, and a synthetic
   matched-target flash/BUP regression comparing headers, events and all
   three banks. A device-identified PKC-only hardware cross-check remains.

9. **Consolidate completeness checks.** Status: complete.
   [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169355).
   Use one required-image validator with variant context. Errors must identify
   `common-N` targets correctly. Parser and prediction entry points must
   remain fail-closed.
   Completed: shared validator, recovery/BUP variant context and regression
   checks for missing images and `common-N` errors.

10. **Remove test-only production code.** Status: complete.
    [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169363).
    Remove `directory_images()` from the installed tool. Rewrite the
    embedded-versus-current-firmware test using explicit test inputs while
    preserving its provenance assertion.
    Completed: removed `directory_images()` and its test-only `add_image()`
    helper. Parser tests retain duplicate/conflicting-image coverage.

11. **Declare the Python requirement.** Status: complete.
    [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169369).
    Document Python 3.11 or later and enforce it in packaging. Do not add a
    compatibility implementation for `hashlib.file_digest`.
    Completed: README requirement and Nix package version assertion.

12. **Simplify packaging.** Status: complete.
    [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#discussion_r4404169376).
    Remove the redundant wrapper and PATH modification. Add install-check
    hooks and test the installed executable with a restricted PATH.
    Include fixture files in the source fileset and stage new files so Nix
    sees them.
    Completed: removed wrapping, added install-check hooks and empty-PATH
    executable check, and included the test directory in the source fileset.

13. **Validate SBK encryption.** Status: partial.
    [Feedback](https://github.com/anduril/jetpack-nixos/pull/583#pullrequestreview-5687276594).
    Test real `enc_signed` flash and BUP artifacts on appropriately fused
    hardware. Compare extracted measurements with logs and live PCR0 values.
    Check independently encrypted builds without assuming PCR equality.
    Document tested combinations and explicitly identify remaining gaps.
    Completed for Thor JP7 on `thor-agx-devkit-fused0`: live fuse read
    reported `boot_security_info=0x228`, the flash reported SBKPKC,
    and matched signed/encrypted flash-initrd and BUP headers, OP-TEE/EFI
    logs and live PCR0 values agree in all three banks before and after
    the capsule update. The event order did not change; firmware digests
    and PCR0 did. Other fused boards/releases and independent key
    combinations have not been validated.

## PCR0 Hardware Test

The downstream helper is in the `user/jhoffer/jetpack_ftpm` worktree under
`pkgs/anduril/nixos/tests/hitl-device-test-functions/optee-pcr.py`.

- Read and replay SHA-256, SHA-384 and SHA-512 PCR0. Require every advertised
  bank to be present.
- Parse logs separately and preserve OP-TEE-before-EFI event order.
  Extend only banks present in each measured event.
- Require artifact prediction, combined-log replay and live TPM values
  to agree for every bank.
- Select firmware variants using EEPROM board identity and fuse reads rather
  than accepting any matching variant.
- Add negative cases for reordered or missing events, duplicate digests,
  incorrect separators, SHA-384/SHA-512-only corruption and mismatched
  artifacts.
- Retain exact artifact manifests, measurements, header excerpts, firmware
  versions and logs from flash and capsule-update runs.

The downstream helper now replays all three banks and checks each
against the live TPM and artifact prediction. Negative unit tests
cover event order, missing events, duplicate digests, separator
corruption, SHA-384/SHA-512-only corruption and mismatched artifacts.
The downstream helper now selects a unique production-mode variant by
matching its board metadata against `tegra-boardspec` (module EEPROM) and
requiring populated PKC and boot-security fuse values from
`nv_fuse_read.sh`. Missing or ambiguous identity fails closed. This covers
the fused Orin and Thor HITL configurations; other fuse modes require
separate validation.

## Execution Order

First, address local provenance, format, diagnostic, documentation and
packaging fixes. Next, add variant metadata, restructure the payload and
expand integrity verification. Then add matched golden captures and run
the hardware matrix. Record partial completion explicitly when hardware
evidence or architectural work remains.

## First-Pass Verification

- `nix build ".#legacyPackages.x86_64-linux.firmwareMeasurements" --no-link`:
  passed all 34 measurement tests and the empty-PATH install check.
- `nix build ".#checks.x86_64-linux.flashInitrd" --no-link`: passed
  signed-firmware passthrough, compressor/prepend assertions, and
  fail-before-RCM checks for changed payloads and missing payload directories.
- `nix build ".#checks.x86_64-linux.formatting" --no-link`: passed.
- Evaluated the Orin Nano multi-variant and Thor T4000 single-variant
  flasher derivations. Embedded and configured signed-firmware derivations
  matched for both configurations.
- `git diff --check`: passed.
- No hardware tests ran and no new golden captures were collected.

## Zstandard Verification

- Measurement package build: passed all 38 tests and the empty-PATH install
  check with the packaged `pyzstd` dependency.
- Flasher regression and repository formatting checks: passed.
- Evaluated the Orin Nano and Thor T4000 recovery initrds. Both select
  `zstd` through the NixOS default, without a compressor override.
- No on-device tests ran.

## JP6/JP7 fTPM Verification

- Orin Nano fused JP6 and JP7 flash/capsule HITL tests passed on
  2026-11-02. Thor AGX JP7 flash/capsule HITL tests passed on
  `thor-agx-devkit-fused0` on 2026-11-03. All six compact boot fixtures
  replay in SHA-256, SHA-384 and SHA-512 and match their signed BCH
  digests and artifact measurements.
- The measurement package passed 41 local tests after adding variant
  metadata. The downstream PCR helper passed five negative/positive
  unit tests and replayed both captured Thor boots in all three banks.
- Runtime-generated multi-variant RCM verification and SBK validation on other
  boards/releases remain open. The fused Thor capture establishes
  independently encrypted JP7 behavior, unlike the synthetic matching test.
