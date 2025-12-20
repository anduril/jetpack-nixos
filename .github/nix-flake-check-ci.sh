#!/usr/bin/env bash

enumerateAttrs() {
  local -r flakeURI=$1

  nix eval --json --apply "builtins.attrNames" "$flakeURI" | jq -cr ".[] | \"$flakeURI.\" + ."
}

currentSystem=$(nix eval --impure --raw --expr "builtins.currentSystem")
checks=$(enumerateAttrs ".#checks.${currentSystem}")

set -x
# Evaluate all nixosConfigurations' toplevel derivation
nix-eval-jobs --flake . --select 'flake: builtins.mapAttrs (f: v: v.config.system.build.toplevel) flake.outputs.nixosConfigurations' "$@"

# Evaluate all packages (impure for builtins.currentSystem)
nix-eval-jobs --flake . --impure --select 'flake: builtins.getAttr builtins.currentSystem flake.outputs.packages' "$@"
# Build all checks
for check in $checks; do
  nix build "$check" "$@"
done
