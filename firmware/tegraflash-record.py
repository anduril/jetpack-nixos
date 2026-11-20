#!/usr/bin/env python3
# Stands in for bootloader/tegraflash.py (base-flash-bins.nix installs it with
# the real script's shebang): appends each call's argv to $TEGRAFLASH_RECORD
# for tegraflash-audit.py, then execs the real script. exec keeps the PID,
# which names tegraflash's work dir (bootloader/<pid>).
import json
import os
import sys

with open(os.environ["TEGRAFLASH_RECORD"], "a") as f:
    f.write(
        json.dumps({"pid": os.getpid(), "cwd": os.getcwd(), "argv": sys.argv[1:]})
        + "\n"
    )
real = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tegraflash_real.py")
os.execv(sys.executable, [sys.executable, real] + sys.argv[1:])
