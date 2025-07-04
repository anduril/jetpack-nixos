# NOTE: All fixups must be at least binary functions to avoid callPackage adding override attributes.
{ cudaAtLeast
, expat
, lib
, python3
, stdenv
, gmp
}:
let
  inherit (lib.attrsets) recursiveUpdate;
  inherit (lib.lists) optionals;
  inherit (lib.strings) optionalString versionAtLeast versionOlder;
  inherit (lib.versions) majorMinor;
  python3MajorMinorVersion = majorMinor python3.version;
in
prevAttrs: {
  allowFHSReferences = true;

  buildInputs =
    prevAttrs.buildInputs or [ ]
    ++ optionals (cudaAtLeast "12") [ gmp ]
    # aarch64, sbsa needs expat
    ++ optionals stdenv.hostPlatform.isAarch64 [ expat ];

  # TODO(@connorbaker): What does CUDA 11.x provide in terms of Python binaries?
  postInstall =
    prevAttrs.postInstall or ""
    # Remove binaries requiring Python3 versions we do not have
    + optionalString (cudaAtLeast "12.5") ''
      echo "removing cuda-gdb-python*-tui binaries for Python 3 versions we do not have"
      find "''${!outputBin:?}/bin" \
        -name cuda-gdb-python\*-tui \
        \( ! -name "cuda-gdb-python${python3MajorMinorVersion}-tui" \) \
        -print -delete
    '';

  passthru = recursiveUpdate (prevAttrs.passthru or { }) {
    brokenConditions = {
      "Unsupported Python 3 version" =
        (cudaAtLeast "12.5")
        && (versionOlder python3MajorMinorVersion "3.8" || versionAtLeast python3MajorMinorVersion "3.13");
    };
  };
}
