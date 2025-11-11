{ buildFromDebs
, l4t-cuda
, l4t-nvsci
, l4t-pva
, l4tMajorMinorPatchVersion
, lib
, stdenv
,
}:
let
  cupvaMajorMinorVersion = {
    "35" = "2.3";
    "36" = "2.5";
  }.${lib.versions.major l4tMajorMinorPatchVersion};
in
buildFromDebs {
  pname = "cupva-${cupvaMajorMinorVersion}-l4t";
  repo = "common";
  buildInputs = [ stdenv.cc.cc.lib l4t-cuda l4t-nvsci l4t-pva ];
  postPatch = ''
    mkdir -p lib
    mv opt/nvidia/cupva-${cupvaMajorMinorVersion}/lib/aarch64-linux-gnu/* lib/
    rm -rf opt
  '';
}
