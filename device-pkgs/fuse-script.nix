{ lib, flash-tools, chipId, fuseArgs ? [] }:
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

  # Make nvidia's odmfuse script happy by adding all this stuff to our PATH
  export PATH=${lib.makeBinPath flash-tools.flashDeps}:$PATH

  # -i chipID needs to be the first entry
  ./odmfuse.sh -i ${chipId} "$@" ${builtins.toString fuseArgs}
''
