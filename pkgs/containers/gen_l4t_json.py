#!/usr/bin/env nix-shell
#!nix-shell -i python -p python3

import json
import os.path
import sys

# Run like ./gen_l4t_json.py ./l4t.csv ./unpackedDebs


def main():
    l4tcsv_filename = sys.argv[1]
    filelist_dir = sys.argv[2]

    l4tfiles = []  # Files we need to extract
    with open(l4tcsv_filename, "r") as l4tcsv:
        for line in l4tcsv:
            filetype, filename = line.split(",")
            filetype = filetype.strip()
            filename = filename.strip()

            if filetype in ["lib", "sym"]:
                l4tfiles.append(filename)
            elif filetype in ["dev", "dir"]:
                # Nothing to extract
                pass
            else:
                raise Exception(f"Don't know how to handle filetype {filetype}")

    output = {}
    for fn in os.listdir(filelist_dir):
        fullpath = os.path.join(filelist_dir, fn)
        if not os.path.isfile(fullpath):
            raise Exception(f"Don't know how to handle {fullpath}")

        files_needed = []
        with open(fullpath, "r") as filelist:
            for debfilename in filelist:
                # filename, stripped off leading "./"
                debfilename = debfilename[1:].strip()

                # Skip directories
                if debfilename.endswith("/"):
                    pass

                # Naive O(n^2) matching used here
                if (debfilename in l4tfiles) or any(
                    debfilename.startswith(l4tdir) for l4tdir in l4tfiles
                ):
                    files_needed.append(debfilename)

            if len(files_needed) > 0:
                output[fn] = files_needed

    print(json.dumps(output, sort_keys=True, indent=2, separators=(",", ": ")))


if __name__ == "__main__":
    main()
