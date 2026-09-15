#!/usr/bin/env bash
set -euo pipefail

enumerateAttrs() {
  local -r flakeURI=$1

  nix eval --json --apply "builtins.attrNames" "$flakeURI" | jq -cr ".[] | \"$flakeURI.\" + ."
}

# nix-eval-jobs streams a JSON line per attribute and exits 0 even when an
# individual attribute fails to evaluate (those lines carry a non-null .error).
# Print every line, then fail the step if any line reported an eval error.
evalJobs() {
  local output
  output=$(nix-eval-jobs "$@")
  printf '%s\n' "$output"
  if printf '%s\n' "$output" | jq -e -c 'select(.error != null)' >/dev/null; then
    echo "error: nix-eval-jobs reported evaluation failures (see .error above)" >&2
    return 1
  fi
}

currentSystem=$(nix eval --impure --raw --expr "builtins.currentSystem")
checks=$(enumerateAttrs ".#checks.${currentSystem}")

set -x
# Evaluate all nixosConfigurations' toplevel derivation
evalJobs --flake . --select 'flake: builtins.mapAttrs (f: v: v.config.system.build.toplevel) flake.outputs.nixosConfigurations' "$@"

# Evaluate all packages (impure for builtins.currentSystem)
evalJobs --flake . --impure --select 'flake: builtins.getAttr builtins.currentSystem flake.outputs.packages' "$@"
# Build all checks
for check in $checks; do
  nix build "$check" "$@"
done
