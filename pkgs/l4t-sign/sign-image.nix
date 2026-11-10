{ lib }:

# Signs one partition image the way flash.sh's batch pass does: NVIDIA's list
# mode (tegraparser --pt, tegrahost --list, [SBK encrypt], tegrasign --list,
# tegrahost --updatesig) over a one-partition layout cut from the resolved one.
# $out holds one file, named as stock flash.idx names that partition's image.

# common: flash-args.nix's arguments (pkgs, name, keys, ...), shared with signFile.
common:
{ partition
, image
, # Input name as tegraflash sees it (e.g. tos-optee_t234.img); output names derive from it.
  # null: `image` is a directory holding one file, under that name.
  fileName ? null
, # Resolved partition layout, e.g. flash.xml.tmp from tegraflash's work dir.
  layout
}:

let
  signing = import ./flash-args.nix { inherit lib; } common;
  inherit (signing) pkgs ratchetBlob chipId pkcFile sbkFile;
in
pkgs.runCommand (if signing.name == null then "signed-${partition}" else signing.name) (signing.runCommandEnv // { passthru = { inherit image; }; }) (signing.setup + ''

  mkdir work
  cd work
  ${if fileName == null then ''
    image=(${image}/*)
    test ''${#image[@]} = 1
    fileName=$(basename "$image")
    install -m 644 "$image" "$fileName"
  '' else ''
    fileName=${lib.escapeShellArg fileName}
    install -m 644 ${image} "$fileName"
  ''}
  install -m 644 ${ratchetBlob} ratchet_blob.bin
  awk -v part=${lib.escapeShellArg partition} -v file="$fileName" '
    /<partition_layout/ { head = $0 }
    /<device / { dev = $0 }
    $0 ~ ("<partition name=\"" part "\"") { keep = 1; print head; print dev }
    keep && /<filename/ { sub(/<filename[^>]*\/>|<filename[^>]*>.*<\/filename>/, "<filename>" file "</filename>") }
    keep { print }
    keep && /<\/partition>/ { print "    </device>"; print "</partition_layout>"; exit }
  ' ${layout} > one.xml
  grep -q '</partition_layout>' one.xml
  cat one.xml
  type=$(xmlstarlet sel -t -v '//partition/@type' one.xml)

  $bl/tegraparser_v2 --pt one.xml

'' + signing.keyAndMode + ''
  $bl/tegrahost_v2 --chip ${chipId} 0 --partitionlayout one.bin --ratchet_blob ratchet_blob.bin --list images_list.xml "$mode"
'' + lib.optionalString (sbkFile != null) ''
  # tegraflash_oem_enc + tegraflash_update_pt_name for the one list entry.
  in=$(xmlstarlet sel -t -v '/file_list/file/@name' images_list.xml)
  base=''${in%.*}
  ext=.''${in##*.}
  ${if signing.t264 then ''
    yaml=kdf_args_$base.yaml
    meta=$(xmlstarlet sel -t -v '/file_list/file/@compress' images_list.xml)
    if [ "$meta" = 1 ]; then meta=4096; fi
  '' else ''
    yaml=''${base}_kdf.yaml
    meta=$(xmlstarlet sel -t -v '/file_list/file/@meta_blob_size' images_list.xml)
  ''}
  {
    echo 'ENC : "OEM"'
    echo 'CHIPID : "${chipId}0 0"'
    ${signing.randomLine}
    if [ "$meta" != 0 ]; then
      echo 'COMPRESS : "TRUE"'
      echo "METABLOBSIZE : \"$meta\""
    else
      echo 'COMPRESS : "FALSE"'
    fi
  } > "$yaml"
  tegrasign --file "$in" ${signing.sbkArgs} --kdf kdf_file="$yaml"
  enc=''${base}_encrypt$ext
  $bl/tegraparser_v2 --pt one.bin --update_part_filename ${lib.escapeShellArg partition} "$type" "$enc"
  list=$(<images_list.xml)
  printf '%s\n' "''${list//"$in"/"$enc"}" > images_list.xml
'' + ''
  tegrasign ${signing.pkcArgs} --list images_list.xml ${signing.pubkeyHashArgs} --sha sha512
  $bl/tegrahost_v2 --chip ${chipId} 0 --partitionlayout one.bin --updatesig images_list_signed.xml \
    ${signing.pubkeyHashArgs}

  signed=$(xmlstarlet sel -t -v '/file_list/file/${if pkcFile == null then "sbk/@encrypt_file" else "pkc/@signed_file"}' images_list.xml)
  mkdir $out
  cp "$signed" $out/
'')
