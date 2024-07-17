{ lib, fetchurl, fetchgit, l4tVersion, fvForEKB, fvForSSK }:

let
  debsJSON = lib.importJSON (./r${lib.versions.majorMinor l4tVersion}-debs.json);
  baseURL = "https://repo.download.nvidia.com/jetson";
  repos = [ "t194" "t234" "common" ];

  fetchDeb = repo: pkg: fetchurl {
    url = "${baseURL}/${repo}/${pkg.filename}";
    sha256 = pkg.sha256;
  };
  debs = lib.mapAttrs (repo: pkgs: lib.mapAttrs (pkgname: pkg: pkg // { src = fetchDeb repo pkg; }) pkgs) debsJSON;

  gitJSON = lib.importJSON (./r${l4tVersion}-gitrepos.json);
  gitRepos = lib.mapAttrs
    (relpath: info: fetchgit {
      inherit (info) url rev hash;
    })
    gitJSON;
in
{
  inherit debs gitRepos;
}
