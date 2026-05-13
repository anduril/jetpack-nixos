{
  stdenv,
  python3,
  python3Packages,
  fetchFromGitHub,
  lib,
}:

let
  # TODO: converge back to upstream uefi-firmware-parser once theopolis/uefi-firmware-parser#146 is available in nixpkgs
  uefi-firmware-parser = python3Packages.buildPythonPackage {
    pname = "uefi-firmware-parser";
    version = "1.13-unstable-08-04-2026";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "elliotberman";
      repo = "uefi-firmware-parser";
      rev = "aaf71c5d2268b67dc64e1315201b2d90c844eaee";
      hash = "sha256-jQB/ZD4fjclaAeuSt0zjZDrpwGh+8ASAqeCtG4VnnmM=";
    };

    build-system = [
      python3Packages.setuptools
      python3Packages.wheel
    ];

    pythonRemoveDeps = [ "future" ];

    pythonImportsCheck = [ "uefi_firmware" ];

    meta = {
      description = "Tool for parsing, extracting, and recreating UEFI firmware volumes";
      homepage = "https://github.com/theopolis/uefi-firmware-parser";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
      mainProgram = "uefi-firmware-parser";
    };
  };
in

stdenv.mkDerivation {
  pname = "patchfv";
  version = "0.1.0";

  src = ./.;

  dontBuild = true;

  buildInputs = [
    (python3.withPackages (p: [
      uefi-firmware-parser
    ]))
  ];

  installPhase = ''
    runHook preInstall

    install -D patchfv.py $out/bin/patchfv
    patchShebangs --host $out/bin/patchfv

    runHook postInstall
  '';

  meta = {
    description = "Tool to patch UEFI firmware volumes, replacing version strings";
    mainProgram = "patchfv";
  };
}
