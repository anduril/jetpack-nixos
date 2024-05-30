#!/usr/bin/env nix-shell
#!nix-shell -i python -p python3 nix-prefetch-git

import json
import re
import subprocess
import sys
import os

VERSION = '36.3'
TAG = 'jetson_' + VERSION

FILENAME = 'r' + VERSION + '-gitrepos.json'

REPOS_TO_SKIP = [
    '3rdparty/dtc' # This doesn't have tags...
]

def fetch_git(url, ref):
    result = subprocess.run(['nix-prefetch-git', '--quiet', url, ref], check=True, capture_output=True)
    return json.loads(result.stdout)

def main():
    script_contents = open(sys.argv[1]).read()
    m = re.search(r'^SOURCE_INFO="(.*?)^"$', script_contents, re.MULTILINE | re.DOTALL)

    if m is None:
        raise Exception("SOURCE_INFO regex did not match")

    source_info = m.group(1).strip()

    data = {}

    # Since theses are bigger files, we do this incrementally
    if os.path.exists(FILENAME):
        with open(FILENAME) as fd:
            data = json.load(fd)

    for line in source_info.split('\n'):
        k, relpath, giturl, _ = line.split(':')

        #giturl = "https://" + giturl
        giturl = "git://" + giturl

        if relpath not in data and relpath not in REPOS_TO_SKIP:
            print(f"Checking out {giturl}")
            data[relpath] = fetch_git(giturl, TAG)

        with open(FILENAME, 'w') as fd:
            fd.write(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))

if __name__ == "__main__":
    main()

