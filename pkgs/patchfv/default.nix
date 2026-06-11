{ writers
, python3Packages
, fetchFromGitHub
, lib
,
}:

let
  # TODO: converge back to upstream uefi-firmware-parser once theopolis/uefi-firmware-parser#146 is available in nixpkgs
  uefi-firmware-parser = python3Packages.buildPythonPackage {
    pname = "uefi-firmware-parser";
    version = "1.14";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "theopolis";
      repo = "uefi-firmware-parser";
      tag = "v1.14";
      hash = "sha256-flBnYDVc0ZAG0wW613XUjAdCuHSn7uw2VDMLRFIgaNY=";
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
      mainProgram = "uefi-firmware-parser";
      platforms = lib.platforms.unix;
    };
  };
in

writers.writePython3Bin "patchfv"
{
  libraries = [ uefi-firmware-parser ];
  # E501: ignore line length
  flakeIgnore = [ "E501" ];
}
  (builtins.readFile ./patchfv.py)
