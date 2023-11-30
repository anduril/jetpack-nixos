{ lib, flash-tools }:
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

  cd bootloader
  bash ./flashcmd.txt
''
