{ lib, runCommand, fd, nixpkgs-fmt }:

runCommand "repo-formatting" { } ''
  ${lib.getExe fd} . -e nix ${../.} | xargs ${lib.getExe nixpkgs-fmt} --check
  touch $out
''
