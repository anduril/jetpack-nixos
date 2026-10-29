{ lib, stdenvNoCC, python3 }:
assert lib.assertMsg (lib.versionAtLeast python3.version "3.11")
  "jetson-firmware-measurements requires Python 3.11 or later";
let
  pythonEnv = python3.withPackages (ps: [ ps.pyzstd ]);
in
stdenvNoCC.mkDerivation {
  pname = "jetson-firmware-measurements";
  version = "1";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./measure.py ./tests ];
  };
  nativeBuildInputs = [ pythonEnv ];
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
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    PATH= "$out/bin/jetson-firmware-measurements" --help >/dev/null
    runHook postInstallCheck
  '';
  meta = {
    description = "Predict Jetson firmware PCRs from prepared flash and capsule payloads";
    mainProgram = "jetson-firmware-measurements";
    platforms = lib.platforms.linux;
  };
}
