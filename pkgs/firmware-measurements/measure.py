#!/usr/bin/env python3

import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import stat
import struct

import pyzstd

# NVIDIA helper revisions and UEFI hash-mask sources are listed in README.md.
FIRMWARE_ORDER = {
    "t234": (b"MB2B", b"TOSB", b"CPBL"),
    "t264": (b"MB2B", b"BL31", b"BL32", b"SECP", b"CPBL"),
}
ALGORITHMS = ("sha256", "sha384", "sha512")
HEADER_SIZE = 0x14A0
BUP_HEADER = struct.Struct("<16sIIIIII")
BUP_ENTRY = struct.Struct("<40sIIII128s")


def read_exact(stream, size):
    data = stream.read(size)
    if len(data) != size:
        raise ValueError("Truncated firmware artifact")
    return data


def skip(stream, size):
    while size:
        data = read_exact(stream, min(size, 1024 * 1024))
        size -= len(data)


def signed_digest(header, platform):
    magic = header[0x1400:0x1404]
    if magic not in FIRMWARE_ORDER[platform]:
        return None
    if len(header) < HEADER_SIZE:
        raise ValueError(f"Truncated {magic.decode()} signed header")
    return magic, header[0x1460:HEADER_SIZE]


def validate_images(platform, images, context=""):
    for magic in FIRMWARE_ORDER[platform]:
        if magic not in images:
            raise ValueError(f"Missing {magic.decode()} firmware image{context}")


def pcr0(platform, images):
    validate_images(platform, images)
    values = {name: bytes(hashlib.new(name).digest_size) for name in ALGORITHMS}
    events = []
    for magic in FIRMWARE_ORDER[platform]:
        measured = images[magic]
        digests = {
            name: measured if name == "sha512" else hashlib.new(name, measured).digest()
            for name in ALGORITHMS
        }
        events.append(
            {
                "name": magic.decode(),
                "pcr": 0,
                "eventType": "EV_POST_CODE",
                "digests": {name: digest.hex() for name, digest in digests.items()},
            }
        )
        for name, digest in digests.items():
            values[name] = hashlib.new(name, values[name] + digest).digest()

    # The pinned NVIDIA UEFI hash masks include only SHA-256 and SHA-384.
    separator = {name: hashlib.new(name, bytes(4)).digest() for name in ALGORITHMS[:2]}
    events.append(
        {
            "name": "separator",
            "pcr": 0,
            "eventType": "EV_SEPARATOR",
            "data": "00000000",
            "digests": {name: digest.hex() for name, digest in separator.items()},
        }
    )
    for name, digest in separator.items():
        values[name] = hashlib.new(name, values[name] + digest).digest()
    return {name: value.hex() for name, value in values.items()} | {"events": events}


def initrd_stream(data):
    if data.startswith(b"\x1f\x8b"):
        return gzip.GzipFile(fileobj=io.BytesIO(data))
    if data.startswith(b"\x28\xb5\x2f\xfd"):
        return pyzstd.ZstdFile(io.BytesIO(data))
    if data.startswith((b"070701", b"070702")):
        return io.BytesIO(data)
    raise ValueError("Recovery initrd requires gzip, zstd or uncompressed newc CPIO")


def initrd_images(data, signed_directory, platform):
    prefix = PurePosixPath(str(signed_directory).lstrip("/"))
    variants = {}
    files = []
    contents = {}
    with initrd_stream(data) as stream:
        while True:
            header = read_exact(stream, 110)
            if header[:6] not in (b"070701", b"070702"):
                raise ValueError("Unsupported initrd CPIO format")
            fields = [
                int(header[offset : offset + 8], 16) for offset in range(6, 110, 8)
            ]
            inode, mode, _, _, links, _, size, major, minor, _, _, namesize, _ = fields
            if not namesize:
                raise ValueError("Empty CPIO filename")
            encoded = read_exact(stream, namesize)
            if encoded[-1:] != b"\0":
                raise ValueError("Invalid CPIO filename")
            name = PurePosixPath(encoded[:-1].decode().lstrip("/"))
            skip(stream, -(110 + namesize) % 4)
            if str(name) == "TRAILER!!!":
                if size:
                    raise ValueError("Invalid CPIO trailer size")
                while padding := stream.read(1024 * 1024):
                    if any(padding):
                        raise ValueError(
                            "Recovery initrd requires a single CPIO archive; "
                            "nonpadding data follows the trailer"
                        )
                break
            first = read_exact(stream, min(size, HEADER_SIZE))
            skip(stream, size - len(first))
            skip(stream, -size % 4)
            if not stat.S_ISREG(mode):
                continue
            key = (major, minor, inode) if links > 1 else str(name)
            if size:
                measured = signed_digest(first, platform)
                if measured is not None:
                    contents[key] = measured
            if name.is_relative_to(prefix):
                relative = name.relative_to(prefix)
                if len(relative.parts) == 2:
                    files.append((relative.parts[0], key))

        for variant, key in files:
            if key not in contents:
                continue
            magic, digest = contents[key]
            images = variants.setdefault(variant, {})
            if magic in images and images[magic] != digest:
                raise ValueError(f"Conflicting {magic.decode()} images in {variant}")
            images[magic] = digest
    if not variants:
        raise ValueError("No signed firmware found in the recovery initrd")
    for variant, images in variants.items():
        validate_images(platform, images, f" in recovery initrd variant {variant}")
    return variants


def boot_ramdisk(data):
    if data[:8] != b"ANDROID!" or len(data) < 44:
        raise ValueError("Invalid Android boot image")
    kernel_size, _, size = struct.unpack_from("<III", data, 8)
    page_size, version = struct.unpack_from("<II", data, 36)
    if version > 2 or page_size < 512 or page_size & (page_size - 1):
        raise ValueError("Unsupported Android boot image layout")
    offset = page_size + (kernel_size + page_size - 1) // page_size * page_size
    if not size or offset + size > len(data):
        raise ValueError("Invalid Android boot ramdisk size")
    return data[offset : offset + size]


def board_specs_match(left, right):
    left_fields = left.split("-")
    right_fields = right.split("-")
    return len(left_fields) == len(right_fields) and all(
        not left or not right or left == right
        for left, right in zip(left_fields, right_fields)
    )


def bup_images(data, platform):
    if len(data) < BUP_HEADER.size:
        raise ValueError("Truncated BUP header")
    magic, _, blob_size, header_size, count, kind, uncompressed_size = (
        BUP_HEADER.unpack_from(data)
    )
    table_end = header_size + count * BUP_ENTRY.size
    if magic.rstrip(b"\0") != b"NVIDIA__BLOB__V3" or kind != 0:
        raise ValueError("Unsupported BUP format")
    if blob_size != len(data) or uncompressed_size != blob_size:
        raise ValueError("Invalid or compressed BUP size")
    if header_size < BUP_HEADER.size or table_end > blob_size:
        raise ValueError("Invalid BUP entry table")
    records = []
    specs = set()
    for index in range(count):
        encoded_name, offset, size, _, mode, encoded = BUP_ENTRY.unpack_from(
            data, header_size + index * BUP_ENTRY.size
        )
        name = encoded_name.split(b"\0", 1)[0].decode()
        spec = encoded.split(b"\0", 1)[0].decode()
        if mode not in (0, 1, 2):
            raise ValueError("Unsupported BUP update mode")
        if offset < table_end or offset + size > blob_size:
            raise ValueError("Invalid BUP image bounds")
        if spec:
            specs.add(spec)
        measured = signed_digest(
            data[offset : offset + min(size, HEADER_SIZE)], platform
        )
        records.append((name, spec, mode, measured))
    targets = []
    for spec in sorted(specs):
        fields = spec.split("-")
        if len(fields) < 5 or fields[4] not in ("0", "1"):
            raise ValueError(f"Invalid BUP board specification: {spec}")
        targets.append((spec, spec, 2 if fields[4] == "1" else 1))
    if not targets:
        modes_by_name = {}
        for name, _, mode, _ in records:
            modes_by_name.setdefault(name, set()).update(
                (1, 2) if mode == 0 else (mode,)
            )
        supported_modes = {1, 2}.intersection(*modes_by_name.values())
        if not supported_modes:
            raise ValueError("No common BUP fuse mode applies to every image")
        targets = [(f"common-{mode}", "", mode) for mode in sorted(supported_modes)]
    variants = {}
    for key, spec, mode in targets:
        selected = {}
        # FwPackageGetImageIndex keeps the first wildcard board match,
        # replacing a common fallback if one was selected earlier.
        for name, source, update_mode, measured in records:
            if update_mode not in (0, mode) or (
                source and not board_specs_match(source, spec)
            ):
                continue
            if name not in selected or (source and not selected[name][0]):
                selected[name] = (source, measured)
        images = {}
        for _, measured in selected.values():
            if measured is None:
                continue
            magic, digest = measured
            if magic in images and images[magic] != digest:
                raise ValueError(f"Conflicting {magic.decode()} in BUP variant {key}")
            images[magic] = digest
        validate_images(platform, images, f" in BUP variant {key}")
        variants[key] = images
    if not variants:
        raise ValueError("No signed firmware variants found in BUP")
    return variants


def measurements(platform, kind, artifact, source, signed_directory=None):
    with artifact.open("rb") as stream:
        artifact_digest = hashlib.file_digest(stream, "sha256").hexdigest()
    result = {
        "version": 1,
        "platform": platform,
        "artifact": {
            "type": kind,
            "file": artifact.name,
            "sha256": artifact_digest,
        },
    }
    if platform not in FIRMWARE_ORDER:
        return result | {"pcr0": None, "reason": "Firmware PCR 0 layout is unsupported"}
    if kind == "uefiCapsuleUpdate":
        variants = bup_images(source.read_bytes(), platform)
        with source.open("rb") as stream:
            result["artifact"]["bupSha256"] = hashlib.file_digest(
                stream, "sha256"
            ).hexdigest()
    elif kind == "initrdFlashScript":
        data = source.read_bytes()
        if data.startswith(b"ANDROID!"):
            data = boot_ramdisk(data)
        if signed_directory is None:
            raise ValueError("Recovery initrd requires the embedded signed directory")
        variants = initrd_images(data, signed_directory, platform)
    else:
        raise ValueError(f"Unknown artifact type: {kind}")
    return result | {
        "pcr0": {
            "variants": {
                name: pcr0(platform, images)
                for name, images in sorted(variants.items())
            }
        }
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("platform")
    parser.add_argument("kind", choices=("initrdFlashScript", "uefiCapsuleUpdate"))
    parser.add_argument("artifact", type=Path)
    parser.add_argument("source", type=Path)
    parser.add_argument("--signed-directory", type=Path)
    args = parser.parse_args()
    print(
        json.dumps(
            measurements(
                args.platform,
                args.kind,
                args.artifact,
                args.source,
                args.signed_directory,
            ),
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
