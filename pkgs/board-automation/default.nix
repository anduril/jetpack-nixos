{ stdenv
, bspSrc
, l4tVersion
, python3  # python3 is required for nvtopo.py
, makeWrapper
}:

stdenv.mkDerivation {
  pname = "board-automation";
  version = l4tVersion;

  src = bspSrc;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    python3
  ];

  patches = [ ./board-automation.patch ];

  dontConfigure = true;
  dontBuild = true;
  noDumpEnvVars = true;

  postPatch = ''
    substituteInPlace tools/board_automation/nvtopo.py --replace "#!/usr/bin/env python" "#!/usr/bin/env python3"
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp tools/board_automation/* $out/bin
  '';
}
