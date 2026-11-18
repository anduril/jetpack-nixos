#!/usr/bin/env bash
set -euo pipefail

# PART_NAME BOARD_SPECIFIC OP_MODE_SPECIFIC
awk '/^'"$socFamily"'_bl_table=\(/ { t = 1; next } t && /^\)/ { exit } t && /^\t\x27/ { gsub(/\x27/, ""); print $1, $3, $4 }' \
  "$bupGen" >table
test -s table
date=$(sed -nE '1s/.*DATE: (.*)/\1/p' "$release")
stamp=$(TZ=UTC date -d "$date" +%Y%m%d%H%M%S)

# $1 variant dir, $2 own baseColdboot, $3 variant0's, $4 first with the same
# fuselevel; then partition=leaf pairs.
variant() {
  local dir=$out/$1 own=$2 common=$3 commonOpMode=$4
  shift 4
  # The common leaves are signed with variant0's ratchet levels; fail the build
  # if this variant's ever differ, rather than ship images with the wrong ones.
  cmp $own/ratchet_blob.bin $common/ratchet_blob.bin
  declare -A leaf=()
  for pair in "$@"; do leaf[${pair%%=*}]=${pair#*=}; done
  mkdir -p $dir
  sed 's/, /|/g' $own/images/flash.idx | while IFS='|' read -r num loc start size file _ attrs _; do
    part=${loc##*:}
    base=${part#[AB]_}
    read -r _ board opmode < <(grep "^A_$base \|^$part " table || echo "- 1 1")
    how=copy
    if [[ -z "$file" ]]; then
      src=
    elif [[ -n "${leaf[$base]-}" ]]; then
      src=$(echo ${leaf[$base]}/*)
      how=link
    elif [[ "$base" = VER ]]; then
      src=$dir/$file
      {
        head -n 3 $own/images/$file
        echo "$stamp"
        sed -n 5p $own/images/$file
      } >ver
      read -r crc bytes < <(cksum -a crc32b <ver)
      {
        cat ver
        printf 'BYTES:%d CRC32:%X\n' $bytes $crc
      } >$src
    elif [[ "$board" = 0 ]]; then
      ref=$common
      if [[ "$opmode" = 1 ]]; then ref=$commonOpMode; fi
      src=$ref/images/$(awk -F', ' -v l="$loc" '$2 == l { print $5 }' $ref/images/flash.idx)
      how=common
    else
      src=$own/images/$file
    fi
    if [[ -n "$src" ]]; then
      test -f "$src"
      name=$(basename "$src")
      if [[ -e "$dir/$name" ]]; then
        cmp "$src" "$dir/$name"
      elif [[ "$how" = link ]]; then
        ln -s "$src" "$dir/"
      elif [[ "$how" = common ]]; then
        # Shared by the variants, outside flash-from-device's variant glob.
        # No store hash in the name: it would make baseColdboot a reference.
        commonDir=.common/${ref#*-}
        mkdir -p $out/$commonDir
        [[ -e "$out/$commonDir/$name" ]] || cp "$src" "$out/$commonDir/"
        ln -s "../$commonDir/$name" "$dir/"
      else
        cp "$src" "$dir/"
      fi
      echo "$num, $loc, $start, $size, $name, $(stat -L -c %s "$src"), $attrs, $(sha1sum <"$src" | cut -d' ' -f1)"
    else
      echo "$num, $loc, $start, $size, , , $attrs, "
    fi
  done >$dir/flash.idx
}
