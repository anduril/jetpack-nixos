{ lib }:

# Signs one file the way T234 tegraflash signs --bl and the --bins entries
# (tegraflash_oem_sign_file): tegrahost --align, --appendsigheader with the
# partition type's magic, tegrasign over a one-file list, --updatesigheader.
# With an SBK, tegraflash_oem_enc_and_sign_file: tegrasign --kdf encrypts the
# file after --appendsigheader. These are the uncompressed images in the RCM
# blob. $out holds one file, named as tegraflash names it
# (<stem>_sigheader[_encrypt]<ext>.encrypt|.signed). T234 only (its BCH offsets).

# common: as signImage's.
common:
{
  # A directory holding the one input file, under tegraflash's name for it.
  image
, # tegraparser --get_magic <partition type>, e.g. CPBL, DCEF.
  magicId
}:

let
  signing = import ./flash-args.nix { inherit lib; } common;
  inherit (signing) pkgs ratchetBlob chipId pkcFile sbkFile;
in
assert !signing.t264;
pkgs.runCommand (if signing.name == null then "signed-file" else signing.name) (signing.runCommandEnv // { passthru = { inherit image; }; }) (signing.setup + ''

  mkdir work
  cd work
  image=(${image}/*)
  test ''${#image[@]} = 1
  fileName=$(basename "$image")
  base=''${fileName%.*}
  ext=.''${fileName##*.}
  install -m 644 "$image" "''${base}_aligned$ext"
  install -m 644 ${ratchetBlob} ratchet_blob.bin
  $bl/tegrahost_v2 --chip ${chipId} 0 --align "''${base}_aligned$ext"

'' + signing.keyAndMode + ''
  $bl/tegrahost_v2 --chip ${chipId} 0 --magicid ${magicId} --ratchet_blob ratchet_blob.bin \
    --appendsigheader "''${base}_aligned$ext" "$mode"

  sigheader=''${base}_aligned_sigheader$ext
'' + lib.optionalString (sbkFile != null) ''
  # tegraflash_oem_enc
  {
    echo 'ENC : "OEM"'
    echo 'CHIPID : "${chipId}0 0"'
    ${signing.randomLine}
    echo 'COMPRESS : "FALSE"'
  } > "''${sigheader%.*}_kdf.yaml"
  tegrasign --file "$sigheader" ${signing.sbkArgs} --kdf kdf_file="''${sigheader%.*}_kdf.yaml"
  sigheader=''${base}_aligned_sigheader_encrypt$ext
'' + ''
  # The signed section: TFlashT23x's fixed BCH offsets.
  cat > "''${sigheader}_list.xml" <<EOF
  <file_list><file name="$sigheader" offset="4032" length="4160"><sbk encrypt="1" sign="1" encrypt_file="$sigheader.encrypt" hash="$sigheader.hash" /><pkc signature="$sigheader.sig" signed_file="$sigheader.signed" /><ec signature="$sigheader.sig" signed_file="$sigheader.signed" /><eddsa signature="$sigheader.sig" signed_file="$sigheader.signed" /><xmss signature="$sigheader.sig" signed_file="$sigheader.signed" /></file></file_list>
  EOF
  tegrasign ${signing.pkcArgs} --list "''${sigheader}_list.xml" ${signing.pubkeyHashArgs} --sha sha512
  ${if pkcFile == null then ''
    signed=$sigheader.encrypt sig=$sigheader.hash
  '' else ''
    signed=$sigheader.signed sig=$sigheader.sig
  ''}
  $bl/tegrahost_v2 --chip ${chipId} 0 ${signing.pubkeyHashArgs} --updatesigheader "$signed" "$sig" "$mode"

  mkdir $out
  cp "$signed" "$out/''${signed/_aligned/}"
'')
