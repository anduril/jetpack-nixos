# What signImage and signFile share: their first argument, and how flash.sh's
# options and keys reach tegrasign. `setup` makes a writable tegrasign (and runs
# preSignCommands against it); `keyAndMode` sets $key and $mode as
# tegraflash_get_key_mode does.
{ lib }:
{
  # Package set that runs NVIDIA's tools: its runCommand, and the flash-tools of
  # its pkgsBuildBuild. Callers pick it (e.g. via flasherPkgsOr in overlay-with-config.nix).
  pkgs
, # The flash-tools to run, e.g. with flashScriptOverrides.patches; default: the unpatched SDK's.
  flash-tools ? pkgs.pkgsBuildBuild.nvidia-jetpack.flash-tools
, # Derivation name; null: the signer's default.
  name ? null
, ratchetBlob
, chipId
, # As secureBoot.pkcFile/sbkFile: a PEM (T234) or PKC keylist XML (T264), and an SBK hex file.
  pkcFile ? null
, sbkFile ? null
, # flash.sh options, as flashScriptOverrides.flashArgs; read as tegraflash reads them.
  # --hsm: tegrasign takes the keys from the PKCS#11 token that
  # bootloader/tegrasign_v3_softhsm.py names. pkcFile is still read for the T264
  # keylist's active entry; sbkFile only turns SBK on.
  # --disable-random-iv: makes T234 SBK output comparable. Never ship images built with it.
  flashArgs ? [ ]
, # As secureBoot.preSignCommands, applied to `pkgs`.
  preSignCommands ? (_: "")
, requiredSystemFeatures ? [ ]
, # As secureBoot.noChroot.
  noChroot ? false
}:

let
  r39 = lib.versionAtLeast flash-tools.version "39";
  t264 = chipId == "0x26";
  # flash.sh splits flashArgs on whitespace; tegraflash sees these flags.
  flags = lib.concatMap (a: lib.filter (s: lib.isString s && s != "") (builtins.split "[[:space:]]+" a)) flashArgs;
  # r39 flash.sh hands the word after --passthrough to tegraflash unquoted
  # (flash.sh:3311-3312,6050); r36 has no such option.
  passthroughIndices = lib.filter (i: lib.elemAt flags i == "--passthrough") (lib.range 0 (lib.length flags - 1));
  passthrough = lib.optionals (r39 && passthroughIndices != [ ])
    (lib.sublist (lib.last passthroughIndices + 1) 1 flags);
  # tegraflash options the leaves model, and ones that don't touch leaf signing.
  passthroughKnown = [ "--hsm" "--disable_random_iv" "--keep" "--skipuid" ];
  unknownPassthrough = lib.subtractLists passthroughKnown passthrough;
  hsm = lib.elem "--hsm" flags || lib.elem "--hsm" passthrough;
  disableRandomIv = lib.elem "--disable-random-iv" flags || lib.elem "--disable_random_iv" passthrough;
  preSign = preSignCommands pkgs;
  # tegraflash_get_key_mode / tegraflash_sign_images under --hsm: r36 T234 "pkc",
  # r39 T234 "hsm_l4t", T264 hsm_l4t_<LABEL>_<idx> from the active key's file name.
  pkcArgs =
    if !hsm then ''--key "$key"''
    else if t264 then ''--hsm "$(basename "$key" .pem)" --softhsm''
    else if r39 then "--hsm hsm_l4t --softhsm"
    else "--hsm pkc --softhsm";
in
assert sbkFile != null -> pkcFile != null;
assert hsm -> pkcFile != null;
assert lib.assertMsg (passthrough != [ ] -> !lib.any (a: lib.hasInfix "'" a || lib.hasInfix "\"" a) flashArgs)
  "signImage/signFile: quoted flashArgs with --passthrough aren't supported.";
assert lib.assertMsg (unknownPassthrough == [ ])
  "signImage/signFile: --passthrough tegraflash option(s) not supported for per-image signing: ${toString unknownPassthrough}";
{
  inherit pkgs name ratchetBlob chipId pkcFile sbkFile t264 r39 flags passthrough pkcArgs;
  runCommandEnv = { inherit requiredSystemFeatures; } // lib.optionalAttrs noChroot { __noChroot = true; };
  sbkArgs = if hsm then "--hsm sbk --softhsm" else "--key ${lib.escapeShellArg "${sbkFile}"}";
  pubkeyHashArgs = lib.optionalString (pkcFile != null) "--pubkeyhash pub_key.key";
  # The T234 kdf yaml's line; T264 ignores --disable-random-iv (IV 0).
  randomLine = lib.optionalString (!t264 && !disableRandomIv) "echo 'RANDOM : \" IV SALT2 DERSTR \"'";

  setup = ''
    set -euo pipefail
    export PATH=${lib.makeBinPath flash-tools.flashDeps}:$PATH
    export LC_ALL=C PYTHONDONTWRITEBYTECODE=1
    bl=${flash-tools}/bootloader
    # tegrasign writes its temporaries next to its (symlink-resolved) script.
    ts=$TMPDIR/tegrasign
    mkdir $ts
    ln -s $bl/* $ts/
    rm $ts/tegrasign_v3*
    cp $bl/tegrasign_v3* $ts/
  '' + lib.optionalString (preSign != "") ''
    # Stock runs preSignCommands in the L4T tree root; here bootloader/ is $ts,
    # so edits of bootloader/tegrasign_v3_*.py reach the tegrasign that runs.
    mkdir $TMPDIR/l4t
    ln -s ${flash-tools}/* $TMPDIR/l4t/
    ln -sfn $ts $TMPDIR/l4t/bootloader
    chmod u+w $ts/tegrasign_v3*
    cd $TMPDIR/l4t
    ${preSign}
    cd $NIX_BUILD_TOP
  '' + ''
    # tegrasign prints key material: r36 the derived per-image keys, r39 the raw SBK.
    tegrasign() { $ts/tegrasign_v3.py "$@" 2>&1 | sed -E 's/[0-9a-fA-F]{32,}/<redacted>/g'; }
  '';

  keyAndMode = ''
    key=${if pkcFile == null then "None" else lib.escapeShellArg "${pkcFile}"}
    ${lib.optionalString (pkcFile != null && t264) ''
      # flash.sh get_active_key_from_keylist
      key=$(xmlstarlet sel -t -m "/entry_list/entry[@key_id='$(xmlstarlet sel -t -v /entry_list/bct/@active_index "$key")']" -v @key "$key")
    ''}
    tegrasign ${pkcArgs} --getmode mode.txt
    mode=$(cat mode.txt)
    case $mode in
      pkc) mode=oem-rsa ;;
      ec) mode=oem-ecc ;;
      ec521) mode=oem-ecc521 ;;
      eddsa) mode=oem-eddsa ;;
      xmss) mode=oem-xmss ;;
    esac
  '';
}
