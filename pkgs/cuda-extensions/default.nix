{ lib
,
}:
finalAttrs: prevAttrs:
let
  packages = lib.packagesFromDirectoryRecursive {
    inherit (finalAttrs) callPackage;
    directory = ./.;
  };
in
{
  inherit (packages) vpi vpi-firmware;
}
