{ lib, stdenvNoCC, python3, makeWrapper }:
stdenvNoCC.mkDerivation {
  pname = "jetson-firmware-measurements";
  version = "1";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./measure.py ./tests/test_measure.py ];
  };
  nativeBuildInputs = [ makeWrapper python3 ];
  dontConfigure = true;
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -B -m unittest discover -s tests -v
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 measure.py "$out/bin/jetson-firmware-measurements"
    patchShebangs "$out/bin/jetson-firmware-measurements"
    wrapProgram "$out/bin/jetson-firmware-measurements" \
      --prefix PATH : ${lib.makeBinPath [ python3 ]}
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/jetson-firmware-measurements" --help >/dev/null
  '';
  meta = {
    description = "Predict Jetson firmware PCRs from prepared flash and capsule payloads";
    mainProgram = "jetson-firmware-measurements";
    platforms = lib.platforms.linux;
  };
}
