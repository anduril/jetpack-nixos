# baseColdboot@variant: NVIDIA's `flash.sh --no-flash --sign` for one variant,
# with stubbed UEFI, OP-TEE/ATF, EKS and kernel DTB (jetpack-nixos's are signed as leaves).
# $out keeps flash.idx and its images, the resolved layout, ratchet blob, BR-BCT,
# the overlay set, and the dce and other inputs our leaves need.
# In `rcm` mode (baseRcm@variant), runs `--rcm-boot` instead, with a dummy kernel
# and initrd: $out keeps rcmbootcmd.txt, blob.xml and the referenced files, the
# boot.img parameters and the ramcode, besides the layout files above.
{ lib, pkgs, runCommand, writeText, cfg, jetpack, variant, key, mode ? "coldboot", inputs ? [ ], additionalDtbOverlays ? [ ] }:
let
  signedDir = if cfg.firmware.secureBoot.sbkFile != null then "enc_signed" else "signed";
  model = writeText "tegraflash-model.json" (builtins.toJSON (import ./tests/tegraflash-model.nix {
    inherit lib jetpack mode variant;
    signing = import ../pkgs/l4t-sign/flash-args.nix { inherit lib; } {
      inherit pkgs;
      flash-tools = jetpack.l4tFlashTools;
      ratchetBlob = null;
      inherit (jetpack) chipId;
      inherit (cfg.flashScriptOverrides) flashArgs;
      inherit (cfg.firmware.secureBoot) pkcFile sbkFile;
    };
  }));
in
assert lib.assertMsg (builtins.elem mode [ "coldboot" ])
  "base-flash-bins: expected coldboot or rcm mode";
runCommand "nv-${mode}-${cfg.name}-${key}${jetpack.l4tMajorMinorPatchVersion}"
  (cfg.firmware.secureBoot.derivationAttrs // { passthru.tegraflashModel = model; })
  (jetpack.mkFlashScript jetpack.l4tFlashTools ({
    uefi-firmware = null;
    tosImage = null;
    eksFile = null;
    dtbsDir = null;
    flashCommands = ''
      ${cfg.firmware.secureBoot.preSignCommands pkgs}
      mkdir -p $out/images $out/overlaySet $out/dce $out/inputs
      mv bootloader/tegraflash.py bootloader/tegraflash_real.py
      [[ $(head -c2 bootloader/tegraflash_real.py) = '#!' ]]
      { head -n1 bootloader/tegraflash_real.py; tail -n +2 ${./tegraflash-record.py}; } > bootloader/tegraflash.py
      chmod +x bootloader/tegraflash.py
      export TEGRAFLASH_RECORD=$TMPDIR/tegraflash.jsonl
      ${lib.concatStringsSep " " [
        "BOARDID=${variant.boardid}"
        "BOARDSKU=${variant.boardsku}"
        "FAB=${variant.fab}"
        "BOARDREV=${variant.boardrev}"
        "FUSELEVEL=${variant.fuselevel}"
        "CHIPREV=${variant.chiprev}"
        (lib.optionalString (variant.chipsku != null) "CHIP_SKU=${variant.chipsku}")
        (lib.optionalString (variant.ramcode != null) "RAMCODE=${variant.ramcode}")
        "./flash.sh"
        (lib.optionalString (cfg.flashScriptOverrides.partitionTemplate != null) "-c flash.xml")
        "--no-root-check"
        "--no-flash"
        "--sign"
        "--debug" # keeps tegraflash's work dir (--keep)
        (builtins.toString cfg.flashScriptOverrides.flashArgs)
      ]} 2>&1 | sed -E "s/[0-9a-fA-F]{32,}/<redacted>/g"
      # tegraflash's work dirs, sign pass first; the audit also writes
      # overlaySet/, dce/ and ramcode from the sign pass's argv.
      python3 ${./tests/tegraflash-audit.py} ${model} $TEGRAFLASH_RECORD $out > $TMPDIR/workdirs
      { read -r work; read -r rcm || :; } < $TMPDIR/workdirs

      signed=bootloader/${signedDir}
      cp $signed/flash.idx $out/images/
      # Column 5 of flash.idx is the image file. Signed ones live in $signed;
      # the rest come straight from bootloader/.
      while IFS=", " read -r _ _ _ _ partfile _; do
        if [[ -n "$partfile" && ! -e "$out/images/$partfile" ]]; then
          if [[ -f "$signed/$partfile" ]]; then cp "$signed/$partfile" $out/images/; else cp "bootloader/$partfile" $out/images/; fi
        fi
      done < $signed/flash.idx
      cp -L $work/flash.xml.tmp $work/ratchet_blob.bin $out/
      ${lib.optionalString (jetpack.socType == "t234") "cp $signed/br_bct_b_BR.bct $out/"}
    '' +
      lib.concatMapStringsSep "\n" (f: "cp -L $work/${f} $out/inputs/\n") inputs;
  }))
