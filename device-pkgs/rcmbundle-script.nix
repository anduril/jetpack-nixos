{ lib, rcmBundle, detect, socType, chipId, bundleRoot ? null }:
let
  keys = lib.attrNames rcmBundle;
  bundles = lib.mapAttrs
    (key: path:
      if bundleRoot == null then path else "${bundleRoot}/${key}")
    rcmBundle;
in
''
  set -euo pipefail

  # Variant selection: rcmBundle per firmware.variants entry, keyed by its
  # signedFirmware directory name. --variant <key> picks one; without it, a
  # single-variant config uses its only one, others detect the board over RCM
  # (detect resets it to recovery; rcmbootcmd.txt starts a new session).
  # --usb-instance <busnum-devpath> picks the device when several are connected.
  # shellcheck source=${../firmware/rcm-select-variant.sh}
  source ${../firmware/rcm-select-variant.sh}
  declare -A bundles=(${lib.concatStringsSep " " (lib.mapAttrsToList (k: b: "[${lib.escapeShellArg k}]=${b}") bundles)})
  variant=
  usb_instance=
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --variant)
        variant=''${2:?--variant needs a value}
        shift 2
        ;;
      --usb-instance)
        usb_instance=''${2:?--usb-instance needs a value}
        shift 2
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done
  inst=$(rcm_usb_instance ${chipId} "$usb_instance")
  if [[ -z "$variant" ]]; then
    ${if lib.length keys == 1 then "variant=${lib.escapeShellArg (lib.head keys)}" else "variant=$(${lib.getExe detect} \"$inst\")"}
  fi
  if [[ -z "''${bundles[$variant]-}" ]]; then
    echo "Unknown variant $variant, expected one of: ''${!bundles[*]}" >&2
    exit 1
  fi

  if [[ -z ''${WORKDIR-} ]]; then
    WORKDIR=$(mktemp -d)
    function on_exit() {
      rm -rf "$WORKDIR"
    }
    trap on_exit EXIT
  fi

  cp -r "''${bundles[$variant]}"/. "$WORKDIR"
  chmod -R u+w "$WORKDIR"
  cd "$WORKDIR"

  (cd blob && ../tegrahost_v2 --chip ${chipId} 0 --generateblob blob.xml ../blob.bin)

  head -n 1 rcmbootcmd.txt | rcm_with_instance "$inst" | bash
  ${lib.optionalString (socType == "t264") ''
    # tegraflash_rcmboot waits this long between the BootROM and MB1 stages.
    sleep 10
  ''}
  tail -n +2 rcmbootcmd.txt | rcm_with_instance "$inst" | bash
''
