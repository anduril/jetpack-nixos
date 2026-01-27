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
  cupvaMajorMinorVersion = lib.getAttr (lib.versions.major l4tMajorMinorPatchVersion) {
    "35" = "2.3";
    "36" = "2.5";
    "38" = "2.6";
  };
in
buildFromDebs {
  pname = "cupva-${cupvaMajorMinorVersion}-l4t";
  repo = "common";
  buildInputs = [ stdenv.cc.cc.lib l4t-cuda l4t-nvsci l4t-pva ];
  # Everything is deeply nested in opt, so we need to move it to the top-level.
  preDebNormalization = ''
    pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null
    mv --verbose --no-clobber "$PWD/opt/nvidia/cupva-${cupvaMajorMinorVersion}/lib/aarch64-linux-gnu" "$PWD/lib"
    nixLog "removing $PWD/opt"
    rm --recursive --dir "$PWD/opt" || {
      nixErrorLog "$PWD/opt contains non-empty directories: $(ls -laR "$PWD/opt")"
      exit 1
    }
    popd >/dev/null
  '';
}
