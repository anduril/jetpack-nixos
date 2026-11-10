#!/usr/bin/env python3
# tegraflash's bldtb steps: tegraflash_add_odm_data_to_dtb, then
# concat_file_4k + tegraflash_concat_overlay_dtb (tegraflash_internal.py).
import argparse
import io
import os

import pyfdt


def pad_4k(f):
    f.write(bytearray(-f.tell() % 0x1000))


parser = argparse.ArgumentParser()
# r39 skips `-del` tokens; its removal of them is a no-op (NameError on `cfg`, swallowed).
parser.add_argument("--drop-del", action="store_true")
parser.add_argument("out_dir")
parser.add_argument("dtb_dir")
parser.add_argument("overlay_set")
args = parser.parse_args()


def read(name):
    path = os.path.join(args.overlay_set, name)
    return open(path).read().strip() if os.path.exists(path) else ""


odmdata = read("odmdata")
overlays = [o for o in read("order").split(",") if o]
dtb_name = read("dtb")
dtb_path = os.path.join(args.dtb_dir, dtb_name)

with open(dtb_path, "rb") as f:
    dtb = f.read()

if odmdata:
    fdt = pyfdt.FdtBlobParse(io.BytesIO(dtb)).to_fdt()
    chosen = fdt.resolve_path("/chosen")
    if not chosen:
        chosen = pyfdt.FdtNode("chosen")
        fdt.resolve_path("/").append(chosen)
    if chosen._find("odm-data"):
        chosen.remove("odm-data")
    odm_node = pyfdt.FdtNode("odm-data")
    for prop in [t.strip() for t in odmdata.split(",") if t.strip()]:
        if not (args.drop_del and prop.endswith("-del")):
            odm_node.insert(0, pyfdt.FdtProperty(prop))
    chosen.append(odm_node)
    dtb = fdt.to_dtb()

with open(os.path.join(args.out_dir, dtb_name), "wb") as out:
    out.write(dtb)
    for overlay in overlays:
        pad_4k(out)
        with open(os.path.join(args.overlay_set, overlay), "rb") as f:
            out.write(f.read())
    pad_4k(out)
    out.write(bytearray(64))
