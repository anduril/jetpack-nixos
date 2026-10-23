import gzip
import hashlib
import io
from pathlib import Path
import stat
import struct
import sys
import tempfile
import unittest

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

    def test_missing_and_conflicting_images(self):
        with self.assertRaisesRegex(ValueError, "Missing"):
            measure.pcr0("t234", {})
        images = {}
        measure.add_image(images, image(b"MB2B", 1), "t234")
        measure.add_image(images, image(b"MB2B", 1), "t234")
        with self.assertRaisesRegex(ValueError, "Conflicting"):
            measure.add_image(images, image(b"MB2B", 2), "t234")

    def test_truncated_signed_header(self):
        with self.assertRaisesRegex(ValueError, "Truncated MB2B"):
            measure.signed_digest(image(b"MB2B", 1)[:0x1404], "t234")


class InitrdTests(unittest.TestCase):
    def test_gzip_and_uncompressed(self):
        for platform in measure.FIRMWARE_ORDER:
            data = initrd(platform)
            expected = {
                magic: bytes([index + 1]) * 64
                for index, magic in enumerate(measure.FIRMWARE_ORDER[platform])
            }
            for archive in (data, gzip.compress(data)):
                with self.subTest(platform=platform, compressed=archive != data):
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

    def test_missing_signed_directory(self):
        with self.assertRaisesRegex(ValueError, "No signed firmware"):
            measure.initrd_images(initrd(), Path("/nix/store/other"), "t234")

    def test_android_boot_image(self):
        data = gzip.compress(initrd())
        self.assertEqual(measure.boot_ramdisk(boot_image(data)), data)
        for blob in (b"ANDROID!", boot_image(data, 3), boot_image(data)[:6000]):
            with self.subTest(size=len(blob)), self.assertRaises(ValueError):
                measure.boot_ramdisk(blob)


class BupTests(unittest.TestCase):
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

    def test_conflicting_and_missing_images(self):
        entries = [
            (magic.decode(), image(magic, 1), BOARD_A, 0)
            for magic in measure.FIRMWARE_ORDER["t234"]
        ]
        with self.assertRaisesRegex(ValueError, "Conflicting"):
            measure.bup_images(
                bup(entries + [("extra", image(b"MB2B", 2), BOARD_A, 0)]), "t234"
            )
        with self.assertRaisesRegex(ValueError, "Missing"):
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
            for magic in measure.FIRMWARE_ORDER["t234"]:
                (signed / "board" / magic.decode()).write_bytes(image(magic, 9))
                entries.append(
                    (f"{signed}/board/{magic.decode()}", image(magic, 1), 0, 1)
                )
            artifact = Path(tmp) / "initrd"
            artifact.write_bytes(gzip.compress(cpio(entries)))
            measured = measure.measurements(
                "t234", "initrdFlashScript", artifact, artifact, signed
            )["pcr0"]["variants"]["board"]
            current = measure.pcr0(
                "t234", measure.directory_images(signed, "t234")["board"]
            )
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
