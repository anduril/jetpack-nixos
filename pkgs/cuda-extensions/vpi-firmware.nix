# Needed for vpi${majorVersion}-samples benchmark w/ pva to work
{ dpkg
, runCommand
, nvidia-jetpack
, lib
,
}:
let
  inherit (nvidia-jetpack) l4tMajorMinorPatchVersion debs;

  majorVersion = lib.getAttr (lib.versions.major l4tMajorMinorPatchVersion) {
    "35" = "2";
    "36" = "3";
    "38" = "4";
  };
in
runCommand "vpi${majorVersion}-firmware" { nativeBuildInputs = [ dpkg ]; } ''
  dpkg-deb -x ${debs.common."libnvvpi${majorVersion}".src} source
  install -D source/opt/nvidia/vpi${majorVersion}/lib64/priv/vpi${majorVersion}_pva_auth_allowlist $out/lib/firmware/pva_auth_allowlist
''
