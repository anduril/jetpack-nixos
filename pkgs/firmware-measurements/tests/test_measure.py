import gzip
import hashlib
import io
from pathlib import Path
import stat
import struct
import sys
import tempfile
import unittest

import pyzstd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import measure

SIGNED = Path("/nix/store/fixture-signed")
BOARD_A = "3767-000-0003--1-0-board-"
BOARD_B = "3767-000-0005--1-0-board-"


def image(magic, value):
    data = bytearray(measure.HEADER_SIZE + 8)
    data[0x1400:0x1404] = magic
    data[0x1460:0x14A0] = bytes([value]) * 64
    return bytes(data)


def cpio(entries):
    stream = io.BytesIO()
    for index, (name, data, inode, links) in enumerate(
        entries + [("TRAILER!!!", b"", 0, 1)]
    ):
        name = name.encode() + b"\0"
        fields = (
            inode or index + 1,
            stat.S_IFREG | 0o644,
            0,
            0,
            links,
            0,
            len(data),
            0,
            1,
            0,
            0,
            len(name),
            0,
        )
        stream.write(b"070701" + "".join(f"{value:08x}" for value in fields).encode())
        stream.write(name)
        stream.write(bytes(-stream.tell() % 4))
        stream.write(data)
        stream.write(bytes(-stream.tell() % 4))
    return stream.getvalue()


def initrd(platform="t234", variant="board"):
    return cpio(
        [
            (
                f"./{str(SIGNED).lstrip('/')}/{variant}/{magic.decode()}",
                image(magic, index + 1),
                0,
                1,
            )
            for index, magic in enumerate(measure.FIRMWARE_ORDER[platform])
        ]
    )


def boot_image(ramdisk, version=0):
    page = 2048
    header = bytearray(page)
    header[:8] = b"ANDROID!"
    struct.pack_into("<III", header, 8, 3000, 0, len(ramdisk))
    struct.pack_into("<II", header, 36, page, version)
    return bytes(header) + bytes(4096) + ramdisk + b"UEFI signature"


def bup(entries):
    header_size = measure.BUP_HEADER.size + 8
    offset = header_size + len(entries) * measure.BUP_ENTRY.size
    table = bytearray()
    payload = bytearray()
    for name, data, spec, mode in entries:
        table += measure.BUP_ENTRY.pack(
            name.encode(), offset, len(data), 0, mode, spec.encode()
        )
        payload += data
        offset += len(data)
    return (
        measure.BUP_HEADER.pack(
            b"NVIDIA__BLOB__V3",
            0x01030622,
            offset,
            header_size,
            len(entries),
            0,
            offset,
        )
        + bytes(8)
        + table
        + payload
    )


class PcrTests(unittest.TestCase):
    def test_order_banks_and_separator(self):
        for platform, order in measure.FIRMWARE_ORDER.items():
            with self.subTest(platform=platform):
                images = {
                    magic: bytes([index + 1]) * 64 for index, magic in enumerate(order)
                }
                result = measure.pcr0(platform, images)
                self.assertEqual(
                    [e["name"] for e in result["events"]],
                    [
                        *(magic.decode() for magic in order),
                        "separator",
                    ],
                )
                for algorithm in measure.ALGORITHMS:
                    expected = bytes(hashlib.new(algorithm).digest_size)
                    for magic in order:
                        digest = images[magic]
                        if algorithm != "sha512":
                            digest = hashlib.new(algorithm, digest).digest()
                        expected = hashlib.new(algorithm, expected + digest).digest()
                    if algorithm != "sha512":
                        separator = hashlib.new(algorithm, bytes(4)).digest()
                        expected = hashlib.new(algorithm, expected + separator).digest()
                    self.assertEqual(result[algorithm], expected.hex())
                self.assertNotIn("sha512", result["events"][-1]["digests"])

    def test_missing_images(self):
        for platform, order in measure.FIRMWARE_ORDER.items():
            for missing in order:
                with self.subTest(platform=platform, missing=missing):
                    images = {magic: bytes(64) for magic in order if magic != missing}
                    with self.assertRaisesRegex(
                        ValueError, f"Missing {missing.decode()} firmware image$"
                    ):
                        measure.pcr0(platform, images)

    def test_truncated_signed_header(self):
        with self.assertRaisesRegex(ValueError, "Truncated MB2B"):
            measure.signed_digest(image(b"MB2B", 1)[:0x1404], "t234")


class InitrdTests(unittest.TestCase):
    def test_supported_compression(self):
        for platform in measure.FIRMWARE_ORDER:
            data = initrd(platform)
            expected = {
                magic: bytes([index + 1]) * 64
                for index, magic in enumerate(measure.FIRMWARE_ORDER[platform])
            }
            for name, archive in (
                ("raw", data),
                ("gzip", gzip.compress(data)),
                ("zstd", pyzstd.compress(data)),
            ):
                with self.subTest(platform=platform, compression=name):
                    self.assertEqual(
                        measure.initrd_images(archive, SIGNED, platform),
                        {"board": expected},
                    )

    def test_hard_links_and_directory_boundary(self):
        entries = [
            (f"{SIGNED}/board/MB2B", b"", 50, 2),
            ("other/MB2B", image(b"MB2B", 1), 50, 2),
            (f"{SIGNED}/board/TOSB", image(b"TOSB", 2), 0, 1),
            (f"{SIGNED}/board/CPBL", image(b"CPBL", 3), 0, 1),
            (f"{SIGNED}-wrong/board/MB2B", image(b"MB2B", 9), 0, 1),
        ]
        result = measure.initrd_images(cpio(entries), SIGNED, "t234")
        self.assertEqual(result["board"][b"MB2B"], bytes([1]) * 64)

    def test_multiple_variants(self):
        entries = [
            (f"{SIGNED}/{variant}/{magic.decode()}", image(magic, index + 1), 0, 1)
            for variant in ("board-a", "board-b")
            for index, magic in enumerate(measure.FIRMWARE_ORDER["t234"])
        ]
        self.assertEqual(
            set(measure.initrd_images(cpio(entries), SIGNED, "t234")),
            {"board-a", "board-b"},
        )

    def test_invalid_archive(self):
        for data in (b"", b"070701", bytes(110), initrd()[:-110]):
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                measure.initrd_images(data, SIGNED, "t234")

    def test_archive_padding(self):
        data = initrd()
        expected = measure.initrd_images(data, SIGNED, "t234")
        for archive in (
            data + bytes(512),
            gzip.compress(data + bytes(512)),
            gzip.compress(data) + bytes(512),
            pyzstd.compress(data + bytes(512)),
            pyzstd.compress(data) + pyzstd.compress(bytes(512)),
        ):
            with self.subTest(size=len(archive)):
                self.assertEqual(
                    measure.initrd_images(archive, SIGNED, "t234"), expected
                )

    def test_concatenated_archives_and_trailing_data(self):
        data = initrd()
        for archive in (
            data + data,
            data + bytes(512) + data,
            gzip.compress(data + data),
            gzip.compress(data) + gzip.compress(data),
            pyzstd.compress(data + data),
            pyzstd.compress(data) + pyzstd.compress(data),
            data + b"unexpected",
            gzip.compress(data + b"unexpected"),
            pyzstd.compress(data + b"unexpected"),
        ):
            with self.subTest(size=len(archive)):
                with self.assertRaisesRegex(ValueError, "single CPIO archive"):
                    measure.initrd_images(archive, SIGNED, "t234")

    def test_unsupported_compression(self):
        for magic in (
            b"\xfd7zXZ\x00",
            b"BZh",
            b"\x04\x22\x4d\x18",
        ):
            with self.subTest(magic=magic):
                with self.assertRaisesRegex(
                    ValueError, "gzip, zstd or uncompressed newc"
                ):
                    measure.initrd_images(magic + bytes(110), SIGNED, "t234")

    def test_truncated_and_corrupt_gzip(self):
        data = gzip.compress(initrd())
        with self.assertRaises(EOFError):
            measure.initrd_images(data[:-1], SIGNED, "t234")
        corrupt = bytearray(data)
        corrupt[-8] ^= 1
        with self.assertRaises(gzip.BadGzipFile):
            measure.initrd_images(bytes(corrupt), SIGNED, "t234")

    def test_truncated_and_corrupt_zstd(self):
        data = pyzstd.compress(initrd(), {pyzstd.CParameter.checksumFlag: 1})
        for truncated in (data[:4], data[: len(data) // 2], data[:-1]):
            with self.subTest(size=len(truncated)), self.assertRaises(EOFError):
                measure.initrd_images(truncated, SIGNED, "t234")
        corrupt = bytearray(data)
        corrupt[-1] ^= 1
        with self.assertRaises(pyzstd.ZstdError):
            measure.initrd_images(bytes(corrupt), SIGNED, "t234")

    def test_zstd_frames_without_content_size(self):
        for platform in measure.FIRMWARE_ORDER:
            data = initrd(platform)
            expected = measure.initrd_images(data, SIGNED, platform)
            compressor = pyzstd.ZstdCompressor({pyzstd.CParameter.contentSizeFlag: 0})
            streaming = compressor.compress(data) + compressor.flush()
            multiframe = pyzstd.compress(data[:100]) + pyzstd.compress(data[100:])
            for archive in (streaming, multiframe):
                with self.subTest(platform=platform, size=len(archive)):
                    self.assertEqual(
                        measure.initrd_images(archive, SIGNED, platform), expected
                    )

    def test_zstd_trailing_junk(self):
        data = pyzstd.compress(initrd())
        with self.assertRaises(pyzstd.ZstdError):
            measure.initrd_images(data + b"unexpected", SIGNED, "t234")

    def test_invalid_trailer_size(self):
        data = bytearray(initrd())
        trailer = data.rfind(b"070701")
        struct.pack_into("8s", data, trailer + 54, b"00000001")
        with self.assertRaisesRegex(ValueError, "Invalid CPIO trailer size"):
            measure.initrd_images(bytes(data), SIGNED, "t234")

    def test_duplicate_and_conflicting_images(self):
        entries = [
            (f"{SIGNED}/board/{magic.decode()}", image(magic, index + 1), 0, 1)
            for index, magic in enumerate(measure.FIRMWARE_ORDER["t234"])
        ]
        expected = measure.initrd_images(cpio(entries), SIGNED, "t234")
        for value in (1, 9):
            archive = cpio(
                entries + [(f"{SIGNED}/board/extra-MB2B", image(b"MB2B", value), 0, 1)]
            )
            with self.subTest(value=value):
                if value == 1:
                    self.assertEqual(
                        measure.initrd_images(archive, SIGNED, "t234"), expected
                    )
                else:
                    with self.assertRaisesRegex(ValueError, "Conflicting MB2B"):
                        measure.initrd_images(archive, SIGNED, "t234")

    def test_missing_image_variant_context(self):
        data = cpio([(f"{SIGNED}/board/MB2B", image(b"MB2B", 1), 0, 1)])
        with self.assertRaisesRegex(
            ValueError, "Missing TOSB firmware image in recovery initrd variant board$"
        ):
            measure.initrd_images(data, SIGNED, "t234")

    def test_missing_signed_directory(self):
        with self.assertRaisesRegex(ValueError, "No signed firmware"):
            measure.initrd_images(initrd(), Path("/nix/store/other"), "t234")

    def test_android_boot_image(self):
        for compress in (gzip.compress, pyzstd.compress):
            data = compress(initrd())
            with self.subTest(compression=compress.__module__):
                self.assertEqual(measure.boot_ramdisk(boot_image(data)), data)
                for blob in (
                    b"ANDROID!",
                    boot_image(data, 3),
                    boot_image(data)[:6000],
                ):
                    with self.subTest(size=len(blob)), self.assertRaises(ValueError):
                        measure.boot_ramdisk(blob)


class BupTests(unittest.TestCase):
    def test_board_spec_wildcards_and_field_counts(self):
        specific = BOARD_A.replace("0003--", "0003-A.0-")
        self.assertTrue(measure.board_specs_match(BOARD_A, specific))
        self.assertTrue(measure.board_specs_match(specific, BOARD_A))
        self.assertFalse(measure.board_specs_match(BOARD_A, BOARD_B))
        self.assertFalse(measure.board_specs_match(BOARD_A, BOARD_A + "-"))

    def test_first_matching_board_entry(self):
        specific = BOARD_A.replace("0003--", "0003-A.0-")
        board_entries = [
            ("tos", image(b"TOSB", 2), BOARD_A, 2),
            ("tos", image(b"TOSB", 9), specific, 2),
        ]
        for ordered in (board_entries, list(reversed(board_entries))):
            with self.subTest(first=ordered[0][2]):
                entries = [
                    ("mb2", image(b"MB2B", 1), BOARD_A, 0),
                    ("tos", image(b"TOSB", 3), "", 0),
                    *ordered,
                    ("uefi", image(b"CPBL", 4), "", 0),
                ]
                result = measure.bup_images(bup(entries), "t234")
                expected = ordered[0][1][0x1460:0x14A0]
                self.assertEqual(result[BOARD_A][b"TOSB"], expected)
                self.assertEqual(result[specific][b"TOSB"], expected)

    def test_wildcard_image_for_specific_metadata(self):
        specific = BOARD_A.replace("0003--", "0003-A.0-")
        entries = [
            ("mb2", image(b"MB2B", 1), BOARD_A, 0),
            ("mb1", b"not a PCR0 image", specific, 2),
            ("tos", image(b"TOSB", 2), "", 0),
            ("uefi", image(b"CPBL", 3), "", 0),
        ]
        result = measure.bup_images(bup(entries), "t234")
        self.assertEqual(result[BOARD_A], result[specific])

    def test_common_images_and_specific_override(self):
        entries = [
            ("mb2", image(b"MB2B", 1), BOARD_A, 0),
            ("mb2", image(b"MB2B", 2), BOARD_B, 0),
            ("tos", image(b"TOSB", 3), "", 0),
            ("tos", image(b"TOSB", 4), BOARD_B, 2),
            ("uefi", image(b"CPBL", 5), "", 0),
            ("uefi-B", image(b"CPBL", 5), "", 0),
        ]
        result = measure.bup_images(bup(entries), "t234")
        self.assertEqual(result[BOARD_A][b"TOSB"], bytes([3]) * 64)
        self.assertEqual(result[BOARD_B][b"TOSB"], bytes([4]) * 64)

    def test_all_common_and_separate_fuse_modes(self):
        entries = [
            (magic.decode(), image(magic, mode + 1), "", mode)
            for mode in (1, 2)
            for magic in measure.FIRMWARE_ORDER["t264"]
        ]
        result = measure.bup_images(bup(entries), "t264")
        self.assertEqual(set(result), {"common-1", "common-2"})
        self.assertNotEqual(result["common-1"], result["common-2"])

    def test_all_common_single_fuse_mode(self):
        for platform in measure.FIRMWARE_ORDER:
            for mode in (1, 2):
                for shared in (False, True):
                    with self.subTest(platform=platform, mode=mode, shared=shared):
                        entries = [
                            (
                                magic.decode(),
                                image(magic, index + 1),
                                "",
                                0 if shared and index else mode,
                            )
                            for index, magic in enumerate(
                                measure.FIRMWARE_ORDER[platform]
                            )
                        ]
                        result = measure.bup_images(bup(entries), platform)
                        self.assertEqual(set(result), {f"common-{mode}"})

    def test_all_common_shared_fuse_mode(self):
        entries = [
            (magic.decode(), image(magic, 1), "", 0)
            for magic in measure.FIRMWARE_ORDER["t234"]
        ]
        result = measure.bup_images(bup(entries), "t234")
        self.assertEqual(set(result), {"common-1", "common-2"})
        self.assertEqual(result["common-1"], result["common-2"])

    def test_all_common_unmeasured_mode_restriction(self):
        entries = [
            (magic.decode(), image(magic, 1), "", 0)
            for magic in measure.FIRMWARE_ORDER["t234"]
        ]
        result = measure.bup_images(
            bup(entries + [("mb1", b"not a PCR0 image", "", 2)]), "t234"
        )
        self.assertEqual(set(result), {"common-2"})

    def test_all_common_missing_images_and_incompatible_modes(self):
        with self.assertRaisesRegex(
            ValueError, "Missing TOSB firmware image in BUP variant common-2$"
        ):
            measure.bup_images(bup([("mb2", image(b"MB2B", 1), "", 2)]), "t234")
        entries = [
            ("mb2", image(b"MB2B", 1), "", 1),
            ("tos", image(b"TOSB", 2), "", 2),
            ("uefi", image(b"CPBL", 3), "", 0),
        ]
        with self.assertRaisesRegex(ValueError, "No common BUP fuse mode"):
            measure.bup_images(bup(entries), "t234")

    def test_shared_update_mode_and_production_metadata(self):
        entries = [
            ("mb2", image(b"MB2B", 1), BOARD_A, 0),
            ("tos", image(b"TOSB", 2), "", 0),
            ("uefi", image(b"CPBL", 3), BOARD_A, 0),
            ("mb1", b"not a PCR0 image", BOARD_A, 2),
        ]
        result = measure.bup_images(bup(entries), "t234")
        self.assertEqual(set(result), {BOARD_A})
        self.assertEqual(result[BOARD_A][b"MB2B"], bytes([1]) * 64)

    def test_first_matching_common_entry(self):
        entries = [
            ("mb2", image(b"MB2B", 1), BOARD_A, 0),
            ("tos", image(b"TOSB", 2), "", 0),
            ("tos", image(b"TOSB", 9), "", 2),
            ("uefi", image(b"CPBL", 3), BOARD_A, 0),
        ]
        result = measure.bup_images(bup(entries), "t234")
        self.assertEqual(result[BOARD_A][b"TOSB"], bytes([2]) * 64)

    def test_select_before_filtering_measured_images(self):
        entries = [
            ("mb2", b"not a PCR0 image", BOARD_A, 0),
            ("mb2", image(b"MB2B", 1), BOARD_A, 0),
            ("tos", image(b"TOSB", 2), "", 0),
            ("uefi", image(b"CPBL", 3), "", 0),
        ]
        with self.assertRaisesRegex(ValueError, "Missing MB2B"):
            measure.bup_images(bup(entries), "t234")

    def test_conflicting_and_missing_images(self):
        entries = [
            (magic.decode(), image(magic, 1), BOARD_A, 0)
            for magic in measure.FIRMWARE_ORDER["t234"]
        ]
        with self.assertRaisesRegex(ValueError, "Conflicting"):
            measure.bup_images(
                bup(entries + [("extra", image(b"MB2B", 2), BOARD_A, 0)]), "t234"
            )
        with self.assertRaisesRegex(
            ValueError, f"Missing CPBL firmware image in BUP variant {BOARD_A}$"
        ):
            measure.bup_images(bup(entries[:-1]), "t234")

    def test_invalid_bup(self):
        data = bup(
            [
                (magic.decode(), image(magic, 1), BOARD_A, 0)
                for magic in measure.FIRMWARE_ORDER["t234"]
            ]
        )
        bad_offset = bytearray(data)
        struct.pack_into("<I", bad_offset, measure.BUP_HEADER.size + 8 + 40, 0)
        for blob in (b"", bytes(40), data[:-1], bytes(bad_offset)):
            with self.subTest(size=len(blob)), self.assertRaises(ValueError):
                measure.bup_images(blob, "t234")


class ArtifactTests(unittest.TestCase):
    def test_artifact_digest_and_variants(self):
        with tempfile.TemporaryDirectory() as tmp:
            artifact = Path(tmp) / "initrd"
            artifact.write_bytes(gzip.compress(initrd()))
            result = measure.measurements(
                "t234", "initrdFlashScript", artifact, artifact, SIGNED
            )
            self.assertEqual(
                result["artifact"]["sha256"],
                hashlib.sha256(artifact.read_bytes()).hexdigest(),
            )
            self.assertIn("board", result["pcr0"]["variants"])

    def test_zstd_boot_image_measurements(self):
        with tempfile.TemporaryDirectory() as tmp:
            for platform in measure.FIRMWARE_ORDER:
                artifact = Path(tmp) / "boot.img"
                predictions = []
                for compress in (gzip.compress, pyzstd.compress):
                    artifact.write_bytes(boot_image(compress(initrd(platform))))
                    result = measure.measurements(
                        platform, "initrdFlashScript", artifact, artifact, SIGNED
                    )
                    self.assertEqual(
                        result["artifact"]["sha256"],
                        hashlib.sha256(artifact.read_bytes()).hexdigest(),
                    )
                    predictions.append(result["pcr0"])
                with self.subTest(platform=platform):
                    self.assertEqual(*predictions)

    def test_capsule_digest_uses_final_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "bl_only_payload"
            source.write_bytes(
                bup(
                    [
                        (magic.decode(), image(magic, 1), BOARD_A, 0)
                        for magic in measure.FIRMWARE_ORDER["t234"]
                    ]
                )
            )
            artifact = Path(tmp) / "capsule.Cap"
            artifact.write_bytes(b"capsule" + source.read_bytes() + b"signature")
            result = measure.measurements("t234", "uefiCapsuleUpdate", artifact, source)
            self.assertEqual(
                result["artifact"]["sha256"],
                hashlib.sha256(artifact.read_bytes()).hexdigest(),
            )
            self.assertEqual(
                result["artifact"]["bupSha256"],
                hashlib.sha256(source.read_bytes()).hexdigest(),
            )
            artifact.write_bytes(b"capsule" + source.read_bytes() + b"new signature")
            changed = measure.measurements(
                "t234", "uefiCapsuleUpdate", artifact, source
            )
            self.assertEqual(changed["pcr0"], result["pcr0"])
            self.assertNotEqual(
                changed["artifact"]["sha256"], result["artifact"]["sha256"]
            )

    def test_embedded_images_not_current_signed_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            signed = Path(tmp) / "signed"
            (signed / "board").mkdir(parents=True)
            entries = []
            current_images = {}
            for magic in measure.FIRMWARE_ORDER["t234"]:
                current_header = image(magic, 9)
                (signed / "board" / magic.decode()).write_bytes(current_header)
                current_images[magic] = bytes([9]) * 64
                entries.append(
                    (f"{signed}/board/{magic.decode()}", image(magic, 1), 0, 1)
                )
            artifact = Path(tmp) / "initrd"
            artifact.write_bytes(gzip.compress(cpio(entries)))
            measured = measure.measurements(
                "t234", "initrdFlashScript", artifact, artifact, signed
            )["pcr0"]["variants"]["board"]
            current = measure.pcr0("t234", current_images)
            self.assertNotEqual(measured["sha256"], current["sha256"])

    def test_unsupported_soc(self):
        with tempfile.TemporaryDirectory() as tmp:
            artifact = Path(tmp) / "capsule.Cap"
            artifact.write_bytes(b"unsupported")
            result = measure.measurements(
                "t194", "uefiCapsuleUpdate", artifact, artifact
            )
            self.assertIsNone(result["pcr0"])
            self.assertIn("unsupported", result["reason"])


if __name__ == "__main__":
    unittest.main()
