#!/usr/bin/env nix-shell
#!nix-shell -i python -p "python3.withPackages (ps: with ps; [ debian ])

import gzip
import json
import re
import urllib.request

from debian.debian_support import Version


BASE_URL = 'https://repo.download.nvidia.com/jetson'
REPOS = ['t234', 'common']
VERSION = 'r35.6'

def fetch_debs(url):
    fd = urllib.request.urlopen(url)

    data = {}

    with gzip.GzipFile(fileobj=fd) as file:
        pkg_strings = file.read().decode().strip().split('\n\n')

        for pkg_string in pkg_strings:
            package = re.search(r'^Package: (.*)$', pkg_string, re.MULTILINE).group(1)
            version = re.search(r'^Version: (.*)$', pkg_string, re.MULTILINE).group(1)
            filename = re.search(r'^Filename: (.*)$', pkg_string, re.MULTILINE).group(1)
            sha256 = re.search(r'^SHA256: (.*)$', pkg_string, re.MULTILINE).group(1)
            description = re.search(r'^Description: (.*)$', pkg_string, re.MULTILINE).group(1)
            m_source = re.search(r'^Source: (.*)$', pkg_string, re.MULTILINE)

            if 'meta-package' in description:
                continue

            if package not in data or Version(data[package]['version']) < Version(version):
                data[package] = {
                    'version': version,
                    'filename': filename,
                    'sha256': sha256,
                }
                if m_source is not None:
                    data[package]['source'] = m_source.group(1)

    return data


def main():
    data = {
        repo: fetch_debs(f'{BASE_URL}/{repo}/dists/{VERSION}/main/binary-arm64/Packages.gz')
        for repo in REPOS
    }
    print(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))


if __name__ == "__main__":
    main()
