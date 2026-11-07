#!/usr/bin/env python3
import html
import pathlib
import sys


def main():
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[1] != "--xml"):
        raise ValueError("expected one URI file")
    data = pathlib.Path(sys.argv[-1]).read_bytes().removesuffix(b"\n")
    uri = data.decode("utf-8")
    if not uri.startswith("pkcs11:") or any(
        ord(char) < 32 or ord(char) == 127 for char in uri
    ):
        raise ValueError("file must contain one PKCS#11 URI")
    print(html.escape(uri, quote=True) if len(sys.argv) == 3 else uri)


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, ValueError) as error:
        print(f"pkcs11-uri-from-file: {error}", file=sys.stderr)
        sys.exit(1)
