#!/usr/bin/env python3
# Holds the tegraflash.py calls that tegraflash-record.py recorded during
# base-flash-bins' flash.sh run to tegraflash-model.nix, then writes what the
# sign pass fed the kernel DTB into (overlaySet/, dce/, ramcode) to $out.
# Prints each call's work dir, one per line, in model order.
# Usage: tegraflash-audit.py <model.json> <record.jsonl> <out>
import json
import os
import shutil
import sys
import xml.etree.ElementTree as ET


def parse(argv, flags):
    """argv -> {flag: [value or None]} as tegraflash's getopt reads it, plus errors."""
    seen, errors, i = {}, [], 0
    while i < len(argv):
        tok = argv[i]
        i += 1
        if not tok.startswith("--"):
            errors.append(f"unexpected argument {tok!r}")
            continue
        spec = flags.get(tok)
        if spec is None:
            errors.append(f"unexpected flag {tok}")
            if i < len(argv) and not argv[i].startswith("--"):
                i += 1
            continue
        if spec.get("bool"):
            seen.setdefault(tok, []).append(None)
        elif i < len(argv):
            seen.setdefault(tok, []).append(argv[i])
            i += 1
        else:
            errors.append(f"{tok}: missing value")
    return seen, errors


def active_key(keylist):
    # As flash-args.nix keyAndMode (flash.sh get_active_key_from_keylist).
    root = ET.parse(keylist).getroot()
    index = root.find("bct").get("active_index")
    return next(e.get("key") for e in root.iter("entry") if e.get("key_id") == index)


def check(seen, flags):
    errors = []
    for flag, spec in sorted(flags.items()):
        values = seen.get(flag, [])
        if len(values) not in spec["n"]:
            errors.append(
                f"{flag}: expected {' or '.join(map(str, spec['n']))} time(s), got {len(values)}: {values}"
            )
        want = spec.get("value")
        if want is not None and any(v != want for v in values):
            errors.append(f"{flag}: expected {want!r}, got {values}")
        path = spec.get("path") or (
            spec.get("activeKeyOf") and active_key(spec["activeKeyOf"])
        )
        if path and any(os.path.realpath(v) != os.path.realpath(path) for v in values):
            errors.append(f"{flag}: expected {path}, got {values}")
    return errors


def one(seen, flag):
    return seen[flag][0] if flag in seen else None


def backup_name(infile, stem):
    # tegraflash_internal.tegraflash_create_backup_file's name.
    base, ext = os.path.splitext(infile.replace(stem, ""))
    return base + stem + ext


def dce(seen, work):
    """(dce_bin, dce_with_dtb, base, overlays) as get_dce_with_dtb_filename picks them, or raises."""
    layout_flag = next(
        f for f in ("--cfg", "--coldboot_pt_layout", "--rcmboot_pt_layout") if f in seen
    )
    # <work>/<layout> links to flash.sh's layout; tegraflash rewrites only its .tmp copy.
    root = ET.parse(os.path.join(work, one(seen, layout_flag))).getroot()
    partitions = list(root.iter("partition"))
    dce_node = next(
        (p.find("filename") for p in partitions if p.get("type") == "dce_fw"), None
    )
    if dce_node is None or not (dce_node.text or "").strip():
        raise ValueError("layout has no dce_fw partition with a filename")
    dce_bin = os.path.basename(dce_node.text.strip())

    bins = dict(
        e.strip().split(None, 1) for e in one(seen, "--bins").split(";") if e.strip()
    )
    if bins.get("dce_fw") != dce_bin:
        raise ValueError(
            f"--bins dce_fw is {bins.get('dce_fw')!r}, layout dce_fw is {dce_bin!r}"
        )

    bldtb = one(seen, "--bldtb")
    raw = one(seen, "--rawkerneldtb")
    if raw is not None:
        # leaves.nix takes the raw base as <dtbsDir>/<--bldtb>.
        if raw != "kernel_" + bldtb:
            raise ValueError(f"--rawkerneldtb is {raw!r}, expected 'kernel_{bldtb}'")
        kernel_dtb, base = raw, "raw"
    else:
        # r36 reads --rawkerneldtb from a [A_]kernel-dtb partition; the leaves model none.
        if any(p.get("name") in ("kernel-dtb", "A_kernel-dtb") for p in partitions):
            raise ValueError("layout has a kernel-dtb partition")
        # parse_partitionlayout's bldtb steps: odm-data copy, overlay copy, .updated.
        kernel_dtb, base = bldtb, "bldtb"
        if one(seen, "--odmdata"):
            kernel_dtb = backup_name(kernel_dtb, "_with_odm")
        if "_overlay" not in kernel_dtb:
            kernel_dtb = backup_name(kernel_dtb, "_overlay")
            if "--overlay_dtb" in seen:
                kernel_dtb += ".updated"
    # concatenate_dcebin_kerneldtb: fdtoverlay(K, --dce_overlay_dtb) -> K_with_dce_overlay.
    overlays = one(seen, "--dce_overlay_dtb") or ""
    if overlays:
        stem, ext = os.path.splitext(kernel_dtb)
        kernel_dtb = stem + "_with_dce_overlay" + ext
    dce_with_dtb = (
        os.path.splitext(dce_bin)[0]
        + "_with_"
        + os.path.splitext(os.path.basename(kernel_dtb))[0]
        + ".bin"
    )

    def read(name):
        with open(os.path.join(work, name), "rb") as f:
            return f.read()

    if read(dce_with_dtb) != read(dce_bin) + read(kernel_dtb):
        raise ValueError(f"{dce_with_dtb} is not {dce_bin} + {kernel_dtb}")
    return dce_bin, dce_with_dtb, base, overlays


def main(model_path, record_path, out):
    with open(model_path) as f:
        model = json.load(f)["invocations"]
    with open(record_path) as f:
        calls = [json.loads(line) for line in f]

    errors, parsed = [], []
    if len(calls) != len(model):
        errors.append(
            f"expected {len(model)} tegraflash call(s) ({', '.join(m['role'] for m in model)}), got {len(calls)}"
        )
    for m, call in zip(model, calls):
        seen, errs = parse(call["argv"], m["flags"])
        errs += check(seen, m["flags"])
        errors += [f"{m['role']}: {e}" for e in errs]
        parsed.append(seen)

    try:
        if not errors:
            sign, work = parsed[0], os.path.join(calls[0]["cwd"], str(calls[0]["pid"]))
            dce_bin, dce_with_dtb, base, dce_overlays = dce(sign, work)
    except (OSError, ValueError, StopIteration) as e:
        errors.append(f"sign: dce: {e}")

    if errors:
        print(
            "tegraflash-audit: flash.sh's tegraflash.py calls differ from firmware/tests/tegraflash-model.nix:",
            file=sys.stderr,
        )
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        for call in calls:
            print(f"  recorded: {json.dumps(call['argv'])}", file=sys.stderr)
        sys.exit(1)

    def write(name, text):
        with open(os.path.join(out, name), "w") as f:
            f.write(text)

    # overlaySet: the comma-ordered overlay list, odm-data string and DTB name
    # tegraflash applies to the DTB, and the overlays it applied. Absolute
    # entries (ADDITIONAL_DTB_OVERLAY store paths) are kept as is; the rest
    # are flash.sh's mutated copies (e.g. L4TConfiguration.dtbo), by basename.
    os.makedirs(os.path.join(out, "overlaySet"), exist_ok=True)
    order = one(sign, "--overlay_dtb") or ""
    write("overlaySet/order", order)
    write("overlaySet/odmdata", one(sign, "--odmdata") or "")
    write("overlaySet/dtb", one(sign, "--bldtb"))
    for f in filter(None, order.split(",")):
        if not f.startswith("/"):
            shutil.copy(os.path.join(work, f), os.path.join(out, "overlaySet"))
    # dce-fw is the stock dce.bin with `base` appended: the overlaid bldtb or the raw kernel DTB.
    os.makedirs(os.path.join(out, "dce"), exist_ok=True)
    shutil.copy(os.path.join(work, dce_bin), os.path.join(out, "dce"))
    write("dce/name", dce_with_dtb)
    write("dce/base", base + "\n")
    # The overlays fdtoverlay applied to the dce base DTB, as for overlaySet.
    os.makedirs(os.path.join(out, "dce/overlays"), exist_ok=True)
    write("dce/overlay-order", dce_overlays)
    for f in filter(None, dce_overlays.split(",")):
        if not f.startswith("/"):
            shutil.copy(os.path.join(work, f), os.path.join(out, "dce/overlays"))
    if any(m["role"] == "rcmboot" for m in model):
        write("ramcode", one(sign, "--ramcode") or "")

    for call in calls:
        print(os.path.join(call["cwd"], str(call["pid"])))


if __name__ == "__main__":
    main(*sys.argv[1:])
