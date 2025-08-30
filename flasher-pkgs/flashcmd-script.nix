{ lib, flash-tools, gcc, dtc }:
''
  set -euo pipefail

  if [[ -z ''${WORKDIR-} ]]; then
    WORKDIR=$(mktemp -d)
    function on_exit() {
      rm -rf "$WORKDIR"
    }
    trap on_exit EXIT
  fi

  cp -r ${flash-tools}/. "$WORKDIR"
  chmod -R u+w "$WORKDIR"
  cd "$WORKDIR"

  # bootloader/tegraflash_impl_t234.py needs these to modify dtbs ;(
  export PATH=${lib.makeBinPath [ gcc dtc ]}:$PATH

  cd bootloader
  bash ./flashcmd.txt
''
