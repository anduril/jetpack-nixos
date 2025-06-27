# Needed for vpi${majorVersion}-samples benchmark w/ pva to work
{ debs
, dpkg
, runCommand
, l4tMajorMinorPatchVersion
, lib
,
}:
let
  majorVersion = {
    "35" = "2";
    "36" = "3";
  }.${lib.versions.major l4tMajorMinorPatchVersion};
in
runCommand "vpi${majorVersion}-firmware" { nativeBuildInputs = [ dpkg ]; } ''
  dpkg-deb -x ${debs.common."libnvvpi${majorVersion}".src} source
  install -D source/opt/nvidia/vpi${majorVersion}/lib64/priv/vpi${majorVersion}_pva_auth_allowlist $out/lib/firmware/pva_auth_allowlist
''
