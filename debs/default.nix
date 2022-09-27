{ lib, fetchurl }:

let
  debsJSON = lib.importJSON ./r35.1.json;
  baseURL = "https://repo.download.nvidia.com/jetson";
  repos = [ "t194" "t234" "common" ];

  fetchDeb = repo: pkg: fetchurl {
    url = "${baseURL}/${repo}/${pkg.filename}";
    sha256 = pkg.sha256;
  };
in
lib.mapAttrs (repo: pkgs: lib.mapAttrs (pkgname: pkg: pkg // { src = fetchDeb repo pkg; }) pkgs) debsJSON
