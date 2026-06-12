#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

show_help() {
  cat <<'EOF'
Usage: extract-signed-orin-artifacts.sh [options]

Required when using --sd-image-dir:
  --sd-image-dir PATH   Path to the signed sd-image build output (contains esp.offset, esp.size, root.offset, root.size, and either sd-image/*.img.zst or *.img.zst)

Manual override options:
  --bootaa64 PATH       Path to a pre-extracted BOOTAA64.EFI file
  --kernel PATH         Path to a pre-extracted kernel Image file
  --initrd PATH         Optional initrd blob to stage alongside the kernel
  --dtb PATH            Optional device tree blob to stage alongside the kernel
  --source-dir DIR      Directory containing BOOTAA64.EFI, Image, etc. (shorthand for the two options above)

Generic options:
  --output DIR          Destination directory for the staged artifacts (default: ./signed-artifacts)
  --manifest NAME       Manifest filename relative to the output directory (default: manifest.json)
  --force               Remove the output directory before staging
  -h, --help            Show this help message and exit

Examples:
  # Extract artifacts directly from a signed sd-image result
  extract-signed-orin-artifacts.sh \
    --sd-image-dir /nix/store/...-nixos-image \
    --output /tmp/orin-signed

  # Use pre-extracted files
  extract-signed-orin-artifacts.sh \
    --source-dir /tmp/pre-signed \
    --output /tmp/orin-signed
EOF
}

SD_IMAGE_DIR=""
SOURCE_DIR=""
BOOTAA64_SRC=""
KERNEL_SRC=""
INITRD_SRC=""
DTB_SRC=""
OUTPUT_DIR="signed-artifacts"
MANIFEST_NAME="manifest.json"
FORCE=0
TEMP_STAGE_DIR=""

cleanup_temp() {
  if [[ -n $TEMP_STAGE_DIR && -d $TEMP_STAGE_DIR ]]; then
    rm -rf "$TEMP_STAGE_DIR"
  fi
}

trap cleanup_temp EXIT

die() {
  echo "Error: $*" >&2
  exit 1
}

ZSTD_BIN=${ZSTD_BIN:-$(command -v zstd)}

require_file() {
  local path="$1"
  [[ -f $path ]] || die "Missing file: $path"
}

extract_partition() {
  local image="$1"
  local offset="$2"
  local size="$3"
  local dest="$4"

  dd if=<("$ZSTD_BIN" -dc --long=31 "$image") \
    bs=512 skip="$offset" count="$size" iflag=fullblock status=none \
    of="$dest"
}

stage_from_sd_image() {
  local root="$1"
  [[ -d $root ]] || die "--sd-image-dir must point to a directory"

  for meta in esp.offset esp.size root.offset root.size; do
    require_file "$root/$meta"
  done

  local img
  img=$(find "$root" -maxdepth 1 -name '*.img.zst' -print -quit)
  if [[ -z $img ]]; then
    img=$(find "$root"/sd-image -maxdepth 1 -name '*.img.zst' -print -quit 2>/dev/null || true)
  fi
  [[ -n $img ]] || die "Could not find compressed sd-image inside $root/sd-image or $root"

  TEMP_STAGE_DIR=$(mktemp -d)

  local esp_offset esp_size root_offset root_size
  esp_offset=$(cat "$root/esp.offset")
  esp_size=$(cat "$root/esp.size")
  root_offset=$(cat "$root/root.offset")
  root_size=$(cat "$root/root.size")

  local esp_img="$TEMP_STAGE_DIR/esp.img"
  local root_img="$TEMP_STAGE_DIR/root.img"

  extract_partition "$img" "$esp_offset" "$esp_size" "$esp_img"
  extract_partition "$img" "$root_offset" "$root_size" "$root_img"

  local extracted_boot="$TEMP_STAGE_DIR/BOOTAA64.EFI"
  local extracted_kernel="$TEMP_STAGE_DIR/Image"

  mcopy -n -i "$esp_img" ::EFI/BOOT/BOOTAA64.EFI "$extracted_boot" >/dev/null 2>&1 ||
    die "Failed to extract BOOTAA64.EFI from ESP image"

  if ! debugfs -R "cat /boot/Image" "$root_img" >"$extracted_kernel" 2>/dev/null || [[ ! -s $extracted_kernel ]]; then
    rm -f "$extracted_kernel"

    local esp_kernel_dir="$TEMP_STAGE_DIR/esp-kernel"
    mkdir -p "$esp_kernel_dir"
    mcopy -n -i "$esp_img" ::EFI/nixos/*-Image.efi "$esp_kernel_dir/" >/dev/null 2>&1 || true

    local esp_kernel
    esp_kernel=$(find "$esp_kernel_dir" -maxdepth 1 -name '*-Image.efi' -print -quit)
    if [[ -n $esp_kernel && -s $esp_kernel ]]; then
      cp "$esp_kernel" "$extracted_kernel"
    else
      die "Failed to extract kernel Image from either /boot/Image or EFI/nixos/*-Image.efi"
    fi
  fi

  local candidate_initrd="$TEMP_STAGE_DIR/initrd"
  if debugfs -R "stat /boot/initrd" "$root_img" >/dev/null 2>&1; then
    debugfs -R "cat /boot/initrd" "$root_img" >"$candidate_initrd" 2>/dev/null || true
    if [[ ! -s $candidate_initrd ]]; then
      rm -f "$candidate_initrd"
    else
      INITRD_SRC="$candidate_initrd"
    fi
  fi

  local candidate_dtb_dir="$TEMP_STAGE_DIR/dtb"
  if debugfs -R "stat /boot/dtbs" "$root_img" >/dev/null 2>&1; then
    mkdir -p "$candidate_dtb_dir"
    if debugfs -R "rdump /boot/dtbs $candidate_dtb_dir" "$root_img" >/dev/null 2>&1; then
      DTB_SRC="$candidate_dtb_dir"
    fi
  fi

  BOOTAA64_SRC="$extracted_boot"
  KERNEL_SRC="$extracted_kernel"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --sd-image-dir)
    if ! SD_IMAGE_DIR=$(realpath -e "$2"); then
      die "Unable to resolve signed image directory: $2"
    fi
    shift 2
    ;;
  --bootaa64)
    BOOTAA64_SRC="$2"
    shift 2
    ;;
  --kernel)
    KERNEL_SRC="$2"
    shift 2
    ;;
  --initrd)
    INITRD_SRC="$2"
    shift 2
    ;;
  --dtb)
    DTB_SRC="$2"
    shift 2
    ;;
  --source-dir)
    SOURCE_DIR="$2"
    shift 2
    ;;
  --output)
    OUTPUT_DIR="$2"
    shift 2
    ;;
  --manifest)
    MANIFEST_NAME="$2"
    shift 2
    ;;
  --force)
    FORCE=1
    shift
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    show_help
    exit 1
    ;;
  esac
done

if [[ -n $SD_IMAGE_DIR ]]; then
  stage_from_sd_image "$SD_IMAGE_DIR"
fi

if [[ -n $SOURCE_DIR ]]; then
  BOOTAA64_SRC="${BOOTAA64_SRC:-$SOURCE_DIR/BOOTAA64.EFI}"
  KERNEL_SRC="${KERNEL_SRC:-$SOURCE_DIR/Image}"
  if [[ -z $INITRD_SRC && -f "$SOURCE_DIR/initrd" ]]; then
    INITRD_SRC="$SOURCE_DIR/initrd"
  fi
  if [[ -z $DTB_SRC && -d "$SOURCE_DIR/dtb" ]]; then
    DTB_SRC="$SOURCE_DIR/dtb"
  fi
fi

if [[ -z $BOOTAA64_SRC || -z $KERNEL_SRC ]]; then
  echo "Either --sd-image-dir or both --bootaa64/--kernel must be provided." >&2
  show_help
  exit 1
fi

for required in BOOTAA64_SRC KERNEL_SRC; do
  path="${!required}"
  if [[ ! -f $path ]]; then
    die "Required artifact not found: $path"
  fi
done

if [[ -d $OUTPUT_DIR ]]; then
  if [[ $FORCE -eq 1 ]]; then
    rm -rf "$OUTPUT_DIR"
  else
    die "Output directory $OUTPUT_DIR already exists. Use --force to overwrite."
  fi
fi

mkdir -p "$OUTPUT_DIR"

declare -a manifest_entries

stage_artifact() {
  local name="$1"
  local src="$2"
  [[ -z $src ]] && return
  local dest="$OUTPUT_DIR/$name"

  if [[ -d $src ]]; then
    mkdir -p "$dest"
    cp -a "$src/." "$dest/"
    manifest_entries+=("    \"$name\": { \"source\": \"$src\", \"type\": \"directory\" }")
    return
  fi

  install -Dm0644 "$src" "$dest"
  local sha
  sha=$(sha256sum "$dest" | awk '{print $1}')
  manifest_entries+=("    \"$name\": { \"source\": \"$src\", \"sha256\": \"$sha\" }")
}

stage_artifact "BOOTAA64.EFI" "$BOOTAA64_SRC"
stage_artifact "Image" "$KERNEL_SRC"
stage_artifact "initrd" "$INITRD_SRC"
stage_artifact "dtb" "$DTB_SRC"

manifest_path="$OUTPUT_DIR/$MANIFEST_NAME"
{
  echo "{"
  for ((i = 0; i < ${#manifest_entries[@]}; i++)); do
    entry="${manifest_entries[$i]}"
    if ((i + 1 < ${#manifest_entries[@]})); then
      echo "$entry,"
    else
      echo "$entry"
    fi
  done
  echo "}"
} >"$manifest_path"

echo "Staged artifacts under $OUTPUT_DIR"
echo "Manifest written to $manifest_path"
echo "Use 'flash-<hostname> -s $SD_IMAGE_DIR' to flash directly from the signed sd-image."
