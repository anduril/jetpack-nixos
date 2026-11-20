# rcmDetect: `flash.sh --gen-read-eeprom`, i.e. the signed applet images that read
# a device's EEPROM and chip info over RCM, as NVIDIA's rcmdump_blob.tar unpacked.
# tegrarcm_v2 and chkbdinfo are the host-runnable i386 binaries, not qemu wrappers.
# The host program that runs it is mkRcmDetectVariant.
{ lib, pkgs, runCommand, cfg, jetpack, fuselevel, chipskus }:
rec {
  rcmDetect = runCommand "rcm-detect-${cfg.name}-${jetpack.l4tMajorMinorPatchVersion}"
    cfg.firmware.secureBoot.derivationAttrs
    (jetpack.mkFlashScript jetpack.l4tFlashTools {
      uefi-firmware = null;
      tosImage = null;
      eksFile = null;
      dtbsDir = null;
      partitionTemplate = null;
      additionalDtbOverlays = [ ];
      flashCommands = ''
        ${cfg.firmware.secureBoot.preSignCommands pkgs}
        FUSELEVEL=${fuselevel} ./flash.sh --no-root-check --gen-read-eeprom ${toString cfg.flashScriptOverrides.flashArgs} 2>&1 \
          | sed -E "s/[0-9a-fA-F]{32,}/<redacted>/g"
        mkdir $out
        tar -xf bootloader/rcmdump_blob.tar -C $out
        for f in tegrarcm_v2 chkbdinfo; do
          if [[ -e bootloader/.$f-wrapped ]]; then cp bootloader/.$f-wrapped $out/rcmdump_blob/$f; fi
        done
      '';
    });

  # mkRcmDetectVariant baseRcm: the program for the variants of baseRcm (a
  # baseRcm.<key> set). Its passthru.variantsTable has a key|chipsku|ramcode line
  # per variant in signedFirmware's directory (glob) order: the variant's
  # chipsku (chipskus.<key>, empty if null) and baseRcm's tegraflash --ramcode
  # (empty: none).
  mkRcmDetectVariant = baseRcm:
    let
      variantsTable = cfg.flasherPkgs.runCommand "rcm-variants-${cfg.name}" { } (lib.concatMapStrings
        (k: "printf '%s|%s|%s\\n' ${k} '${toString chipskus.${k}}' \"$(cat ${baseRcm.${k}}/ramcode)\" >> $out\n")
        (lib.attrNames baseRcm));
    in
    cfg.flasherPkgs.writeShellApplication {
      name = "rcm-detect-variant";
      runtimeInputs = with cfg.flasherPkgs; [ coreutils gnugrep gnused ];
      excludeShellChecks = [ "SC1091" ];
      text = ''
        source ${../pkgs/ota-utils/ota_helpers.sh}
        source ${./rcm-select-variant.sh}
        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT
        rcm_read_board ${rcmDetect} ${jetpack.chipId} "$work" "''${1-}"
        rcm_select_variant ${variantsTable} "$work/chkbdinfo" "$work/uid.log" "$work/cvm.bin" "$work/chipinfo.bin"
      '';
      passthru = { inherit variantsTable; };
    };
}
