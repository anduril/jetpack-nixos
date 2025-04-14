# Needed for vpi2-samples benchmark w/ pva to work
{ debs
, dpkg
, runCommand
,
}:
runCommand "vpi2-firmware" { nativeBuildInputs = [ dpkg ]; } ''
  dpkg-deb -x ${debs.common.libnvvpi2.src} source
  install -D source/opt/nvidia/vpi2/lib64/priv/vpi2_pva_auth_allowlist $out/lib/firmware/pva_auth_allowlist
''
