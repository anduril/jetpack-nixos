# NOTE: All fixups must be at least binary functions to avoid callPackage adding override attributes.
{ cudaAtLeast
, expat
, lib
, python3
, stdenv
, gmp
}:
let
  inherit (lib.lists) optionals;
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
    + lib.optionalString (cudaAtLeast "12.5") ''
      pushd "''${!outputBin}/bin" >/dev/null
      nixLog "removing cuda-gdb-python*-tui binaries for Python 3 versions other than ${python3MajorMinorVersion}"
      for pygdb in cuda-gdb-python*-tui; do
        if [[ "$pygdb" == "cuda-gdb-python${python3MajorMinorVersion}-tui" ]]; then
          continue
        fi
        nixLog "removing $pygdb"
        rm -rf "$pygdb"
      done
      unset -v pygdb
      popd >/dev/null
    '';

  brokenAssertions = [
    {
      # TODO(@connorbaker): Figure out which are supported.
      message = "python 3 version is supported";
      assertion = true;
    }
  ];
}
