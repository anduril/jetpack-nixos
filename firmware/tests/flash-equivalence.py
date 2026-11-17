# Compares two signedFirmware trees ($out/<variant>/{flash.idx, files}) per
# flash.idx partition: bytes equal except the fields stock randomizes (GPT GUIDs
# and CRCs, the VER timestamp and CRC). --may-differ partitions are reported, not
# failed. Exits 1 on any other difference.
# --bup: two bup outputs; for bl_only_payload, BUP_generator.py -c header and entry table
# equal but for offsets and sizes, and every -x entry as above.
# --rcm: stock's bootloader/rcmboot_blob against an rcmBundle; per bundle file,
# rcmbootcmd.txt and tegrarcm_v2 equal, other files and blob.bin components as above.
import argparse
import hashlib
import os
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

p = argparse.ArgumentParser()
p.add_argument("ref")
p.add_argument("cand")
p.add_argument("--may-differ", default="")
# PKC: equal outside the PSS fields, and signatures verify when the key is a file
# (a PEM or keylist), not e.g. a pkcs11: URI.
p.add_argument("--pkc")
p.add_argument("--soc", default="t234")
p.add_argument("--bup", metavar="BUP_generator.py")
p.add_argument("--rcm", action="store_true")
args = p.parse_args()
may_differ = set(filter(None, args.may_differ.split(",")))


def rows(d):
    with open(os.path.join(d, "flash.idx")) as f:
        return [line.rstrip("\n").split(", ") for line in f]


def gpt_mask(d):
    for hdr in (512, len(d) - 512):
        if hdr >= 0 and d[hdr : hdr + 8] == b"EFI PART":
            break
    else:
        return d
    n, size = struct.unpack_from("<II", d, hdr + 80)
    ents = hdr - n * size if hdr else hdr + 512
    m = bytearray(d)
    for a, b in [(hdr + 16, hdr + 20), (hdr + 56, hdr + 72), (hdr + 88, hdr + 92)]:
        m[a:b] = bytes(b - a)
    for i in range(n):
        e = ents + i * size + 16
        m[e : e + 16] = bytes(16)
    return bytes(m)


def ver_mask(d):
    lines = d.split(b"\n")
    return b"\n".join(lines[:3] + lines[4:5])


# Digest + PSS signature fields per kind (E7, E11): BCH images; BR-BCT; and
# bct_backup, which holds the BR-BCT at +0 and +16384.
BCH = [(4, 68), (144, 528)]
BR_BCT = {"t234": [(4, 68), (516, 900)], "t264": [(4, 68), (1560, 1944)]}[args.soc]
PSS_FIELDS = {
    "BCT": BR_BCT,
    "BCT_A": BR_BCT,
    "BCT_B": BR_BCT,
    "BCT-boot-chain_backup": BR_BCT + [(a + 16384, b + 16384) for a, b in BR_BCT],
}


def pubkey(spec):
    if not os.path.isfile(spec):
        return None
    from cryptography.hazmat.primitives import serialization

    data = open(spec, "rb").read()
    if data.startswith(b"<?xml"):
        root = ET.fromstring(data)
        index = root.find("bct").get("active_index")
        return pubkey(
            next(e.get("key") for e in root.iter("entry") if e.get("key_id") == index)
        )
    try:
        return serialization.load_pem_private_key(data, None).public_key()
    except ValueError:
        return serialization.load_pem_public_key(data)


key = pubkey(args.pkc) if args.pkc else None


def pkc_equal(part, a, b):
    fields = PSS_FIELDS.get(part, BCH)
    if len(a) != len(b) or not all(
        any(x <= s and e <= y for x, y in fields) for s, e in ranges(a, b)
    ):
        return False
    if fields is BCH and key is not None:
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import padding

        for d in (a, b):
            assert (
                d[4:68] == hashlib.sha512(d[68:8192]).digest()
            ), f"{part}: bad header digest"
            key.verify(
                d[144:528][::-1],
                d[4032:8192],
                padding.PSS(padding.MGF1(hashes.SHA512()), padding.PSS.AUTO),
                hashes.SHA512(),
            )
    return True


def ranges(a, b):
    out, start = [], None
    for i in range(max(len(a), len(b))):
        same = i < len(a) and i < len(b) and a[i] == b[i]
        if not same and start is None:
            start = i
        if same and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, max(len(a), len(b))))
    return out


# Prints and returns whether a/b fail the rules.
def compare(label, part, a, b, same_name):
    fail = False
    if a == b and same_name:
        status = "IDENTICAL"
    elif part.endswith("VER") and ver_mask(a) == ver_mask(b):
        status = "equal outside VER timestamp/CRC"
    elif "gpt" in part and len(a) == len(b) and gpt_mask(a) == gpt_mask(b):
        status = "equal outside GPT GUIDs/CRCs"
    elif args.pkc and same_name and pkc_equal(part, a, b):
        status = "equal outside PSS fields" + (
            ", signatures verify" if part not in PSS_FIELDS and key is not None else ""
        )
    else:
        diff = ranges(a, b)
        status = (
            f"DIFFERS: sizes {len(a)} / {len(b)}, {len(diff)} ranges, first {diff[:4]}"
        )
        if part.split("_", 1)[-1] in may_differ or part in may_differ:
            status += " (allowed)"
        else:
            fail = True
    print(f"{label} {part}: {status}")
    return fail


# Variant dirs as flash-from-device globs them.
def variant_dirs(d):
    return sorted(v for v in os.listdir(d) if not v.startswith("."))


def compare_signed():
    fail = False
    variants = variant_dirs(args.ref)
    if variants != variant_dirs(args.cand):
        print("variant dirs differ:", variants, variant_dirs(args.cand))
        return True
    for v in variants:
        rd, cd = os.path.join(args.ref, v), os.path.join(args.cand, v)
        rr, cr = rows(rd), rows(cd)
        if [r[:4] + r[6:7] for r in rr] != [r[:4] + r[6:7] for r in cr]:
            print(f"{v}: flash.idx layout columns differ")
            fail = True
            continue
        for r, c in zip(rr, cr):
            part = r[1].split(":")[-1]
            if not r[4] and not c[4]:
                continue
            a = open(os.path.join(rd, r[4]), "rb").read()
            b = open(os.path.join(cd, c[4]), "rb").read() if c[4] else b""
            assert (
                c[5] == str(len(b)) and c[7] == hashlib.sha1(b).hexdigest()
            ), f"{v} {part}: idx size/sha1 wrong"
            if r[4] != c[4]:
                print(f"{v} {part}: names {r[4]} / {c[4]}")
            fail |= compare(v, part, a, b, r[4] == c[4])
    return fail


# BUP_generator.py -c -x all: (header lines, entry rows, extraction dir).
# Rows are [part, offset, size, version, op_mode, spec].
def inspect(payload):
    out = tempfile.mkdtemp()
    txt = subprocess.run(
        [args.bup, "-c", "-x", "all", payload],
        env=dict(os.environ, OUT=out, TOP=out),
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    header, table = txt.split("BLOB HEADER:")[1].split("ENTRY TABLE:")
    entries = [
        [c.strip() for c in line.strip().strip("|").split("|")]
        for line in table.splitlines()
        if line.startswith("|")
    ][1:]
    return [l for l in header.splitlines() if "Size" not in l], entries, out


# The extraction name (BUP_generator.py extract_binaries).
def entry_file(e):
    op = {"0": "", "1": "dev", "2": "prod"}[e[4]]
    return (
        "_".join(filter(None, [e[0], op, "" if e[5] == "common" else e[5]]))
        + ".raw.bin"
    )


def compare_bup():
    fail = False
    name = "bl_only_payload"
    rh, re, rd = inspect(os.path.join(args.ref, name))
    ch, ce, cd = inspect(os.path.join(args.cand, name))
    print(f"{name}: {len(re)} / {len(ce)} entries")
    if rh != ch:
        print(f"{name}: headers differ: {rh} / {ch}")
        fail = True
    key = lambda e: [e[0]] + e[3:]
    if [key(e) for e in re] != [key(e) for e in ce]:
        print(f"{name}: entry tables (name, version, op_mode, spec, in order) differ")
        return True
    for r in re:
        f = entry_file(r)
        a = open(os.path.join(rd, f), "rb").read()
        b = open(os.path.join(cd, f), "rb").read()
        assert len(a) == int(r[2]), f"{name} {f}: size"
        fail |= compare(f"{name} {f}", r[0], a, b, True)
    return fail


# tegrahost --generateblob: "blob", 4 zero bytes, 68 bytes that are random,
# seeded by the time in seconds and independent of the content, the entry
# count, then per entry u32 type, offset, 0, size.
def blob_parts(d):
    assert d[:8] == b"blob\0\0\0\0", "not a blob"
    (n,) = struct.unpack_from("<I", d, 76)
    return [
        (t, d[o : o + s])
        for t, o, _, s in struct.iter_unpack("<IIII", d[80 : 80 + 16 * n])
    ]


def compare_rcm():
    fail = False
    rd = os.path.join(args.ref, "bootloader/rcmboot_blob")
    names = sorted(os.listdir(args.cand))
    read = lambda d, f: open(os.path.join(d, f), "rb").read()
    br_bct = read(rd, "br_bct_BR.bct")
    for f in names:
        a, b = read(rd, f), read(args.cand, f)
        if f == "blob.bin":
            ra, rb = blob_parts(a), blob_parts(b)
            print(f"blob.bin: {len(ra)} / {len(rb)} components")
            if [t for t, _ in ra] != [t for t, _ in rb]:
                print(
                    "blob.bin: component types differ:",
                    [t for t, _ in ra],
                    [t for t, _ in rb],
                )
                fail = True
                continue
            for i, ((t, x), (_, y)) in enumerate(zip(ra, rb)):
                part = (
                    "BCT"
                    if x == br_bct
                    else "boot.img" if x[:8] == b"ANDROID!" else f"type-{t}"
                )
                fail |= compare(f"blob.bin {i}", part, x, y, True)
            if a[:8] + a[76:80] == b[:8] + b[76:80]:
                print("blob.bin header: equal outside its random bytes [8,76)")
            else:
                print("blob.bin header: DIFFERS")
                fail = True
        elif f in ("rcmbootcmd.txt", "tegrarcm_v2"):
            print(f"{f}: {'IDENTICAL' if a == b else 'DIFFERS'}")
            fail |= a != b
        else:
            fail |= compare(f, "BCT" if f == "br_bct_BR.bct" else f, a, b, True)
    return fail


fail = compare_bup() if args.bup else compare_rcm() if args.rcm else compare_signed()
print("FAIL" if fail else "PASS")
sys.exit(1 if fail else 0)
