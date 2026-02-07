{ lib
, l4tAtLeast
, runCommand
, dpkg
, debs
, l4tMajorMinorPatchVersion
}:

let
  repo = if l4tAtLeast "38" then "som" else "t234";
in
runCommand "l4t-csv"
{
  nativeBuildInputs = [ dpkg ];
  # We keep track of the file names so we can use them in the module system to enable nvidia-container-toolkit.
  # Also allows us to make sure we're copying over everything we should.
  passthru.fileNames =
    let
      l4tMajorVersion = lib.versions.major l4tMajorMinorPatchVersion;
    in
    if l4tMajorVersion == "35" then
      [ "l4t.csv" ]
    else if l4tMajorVersion == "36" then
      [
        "devices.csv"
        "drivers.csv"
      ]
    else if l4tMajorVersion == "38" then
      [
        "devices.csv"
        "drivers.csv"
      ]
    else
      builtins.throw "unhandled L4T version ${l4tMajorMinorPatchVersion}";
} ''
  mkdir -p $out
  dpkg --fsys-tarfile ${debs.${repo}.nvidia-l4t-init.src} | tar -x ./etc/nvidia-container-runtime/host-files-for-container.d
  cp etc/nvidia-container-runtime/host-files-for-container.d/* $out/
''
