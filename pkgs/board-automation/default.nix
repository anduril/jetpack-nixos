{ stdenv
, bspSrc
, l4tMajorMinorPatchVersion
, python3  # python3 is required for nvtopo.py
, python3Packages
, makeWrapper
}:

stdenv.mkDerivation {
  pname = "board-automation";
  version = l4tMajorMinorPatchVersion;

  src = bspSrc;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    (python3.buildEnv.override {
      extraLibs = [ python3Packages.pyusb ];
    })
  ];

  dontConfigure = true;
  dontBuild = true;
  noDumpEnvVars = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -r tools/board_automation/* $out/bin

    runHook postInstall
  '';

  meta.mainProgram = "boardctl";
}
