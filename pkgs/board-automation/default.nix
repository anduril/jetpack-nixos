{ stdenv
, bspSrc
, l4tMajorMinorPatchVersion
, python3  # python3 is required for nvtopo.py
, makeWrapper
}:

stdenv.mkDerivation {
  pname = "board-automation";
  version = l4tMajorMinorPatchVersion;

  src = bspSrc;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    python3
  ];

  dontConfigure = true;
  dontBuild = true;
  noDumpEnvVars = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp tools/board_automation/* $out/bin

    runHook postInstall
  '';
}
