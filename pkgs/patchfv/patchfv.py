#!/usr/bin/env python3

import logging
from pathlib import Path
import sys
import traceback

import uefi_firmware

logging.basicConfig(level=logging.DEBUG)

def find_and_replace_in_data(data, old_string, new_string, old_string_utf16, new_string_utf16):
    original_len = len(data)
    replacements = 0

    utf8_count = data.count(old_string)
    if utf8_count > 0:
        data = data.replace(old_string, new_string)
        replacements += utf8_count
        print(f"  Found and replaced {utf8_count} UTF-8 occurrence(s)")

    utf16_count = data.count(old_string_utf16)
    if utf16_count > 0:
        data = data.replace(old_string_utf16, new_string_utf16)
        replacements += utf16_count
        print(f"  Found and replaced {utf16_count} UTF-16LE occurrence(s)")

    assert len(data) == original_len, "Replacement strings must be same length as original!"

    return data, replacements

def _patch_firmware_object(object, old_string, new_string, old_string_utf16, new_string_utf16):
    count = 0

    if hasattr(object, "objects") and any(object.objects):
        for subobject in object.objects:
            count += _patch_firmware_object(subobject, old_string, new_string, old_string_utf16, new_string_utf16)
    elif hasattr(object, "data"):
        new_data, count = find_and_replace_in_data(object.data, old_string, new_string, old_string_utf16, new_string_utf16)
        object.data = new_data

    return count


def _patch_firmware_volume(fv_data, old_string, new_string, old_string_utf16, new_string_utf16):
    parser = uefi_firmware.AutoParser(fv_data)
    if not parser.type():
        raise Exception("Error: could not detect firmware volume type")

    print(f"Detected firwmare type: {parser.type()}")
    firmware = parser.parse()

    count = _patch_firmware_object(firmware, old_string, new_string, old_string_utf16, new_string_utf16)

    if count > 0:
        if not hasattr(firmware, "build"):
            raise Exception("Error: cannot rebuild firmware volume")
        fv_data = firmware.build(generate_checksum=True, debug=True)

    return fv_data, count


def patch_firmware_volume(input_path, output_path, old_string, new_string):
    # Convert strings to bytes if needed and create UTF-16LE versions
    if isinstance(old_string, str):
        old_string = old_string.encode('ascii')
    if isinstance(new_string, str):
        new_string = new_string.encode('ascii')

    old_string_utf16 = old_string.decode('ascii').encode('utf-16-le')
    new_string_utf16 = new_string.decode('ascii').encode('utf-16-le')

    print(f"Reading firmware volume from: {input_path}")

    # Read the entire firmware volume
    with open(input_path, 'rb') as f:
        fv_data = f.read()

    print(f"Firmware volume size: {len(fv_data)} bytes")

    total_replacements = 0
    fv_data, total_replacements = _patch_firmware_volume(fv_data, old_string, new_string, old_string_utf16, new_string_utf16)
    print(f"Replaced {total_replacements} via UEFI parsing")

    print("\n=== Final pass on raw firmware data ===")
    modified_data, direct_count = find_and_replace_in_data(fv_data, old_string, new_string, old_string_utf16, new_string_utf16)
    total_replacements += direct_count

    if total_replacements > 0:
        print(f"\n{'='*60}")
        print(f"Total replacements made: {total_replacements}")
        print(f"{'='*60}")

        with open(output_path, 'wb') as f:
            f.write(modified_data)

        print(f"\nPatched firmware written to: {output_path}")
    else:
        with open(output_path, 'wb') as f:
            f.write(fv_data)
        print("\nNo occurrences of the target string found")

def main():
    if len(sys.argv) != 5:
        print("Usage: patchfv <input_fv> <output_fv> <old_string> <new_string>")
        print()
        print("Example: patchfv UEFI_NS.Fv UEFI_NS_patched.Fv '36.5.0-123456789012' '36.5.0-abcdefghijkl'")
        print()
        print("Note: old_string and new_string must be the same length to maintain firmware structure")
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    old_string = sys.argv[3]
    new_string = sys.argv[4]

    if not input_path.exists():
        print(f"Error: Input file not found: {input_path}")
        sys.exit(1)

    if len(old_string) != len(new_string):
        print(f"Error: old_string and new_string must be the same length")
        print(f"  old_string: '{old_string}' ({len(old_string)} chars)")
        print(f"  new_string: '{new_string}' ({len(new_string)} chars)")
        sys.exit(1)

    print(f"Old string: {old_string}")
    print(f"New string: {new_string}")
    print()

    success = patch_firmware_volume(input_path, output_path, old_string, new_string)

    if input_path.stat().st_size == output_path.stat().st_size:
        print("\n✓ Success: Output file size matches input (in-place replacement)")
    else:
        print(f"\n⚠ Warning: File size changed (input: {input_path.stat().st_size}, "
                f"output: {output_path.stat().st_size})")

if __name__ == '__main__':
    main()
