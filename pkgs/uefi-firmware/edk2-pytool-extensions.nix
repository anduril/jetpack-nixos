{
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  setuptools-scm,
  git,
  python3Packages,
  pyyaml,
  semantic-version,
  edk2-pytool-library,
  pefile,
  gitpython,
  openpyxl,
  xlsxwriter,
}:

buildPythonPackage rec {
  pname = "edk2-pytool-extensions";
  version = "0.27.6";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "tianocore";
    repo = "edk2-pytool-extensions";
    rev = "refs/tags/v${version}";
    hash = "sha256-VmYCiqQrznjg1uP31MWO70cnh4EiNdxLENBpA0dUGu8=";
  };

  patches = [
    ./0001-Remove-nuget-download-and-execute-it-without-Mono.patch
  ];

  SETUPTOOLS_SCM_PRETEND_VERSION = version;
  doCheck = false;

  buildInputs = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    edk2-pytool-library
    pefile
    gitpython
    openpyxl
    xlsxwriter
  ];

  propagatedBuildInputs = [
    pyyaml
    setuptools
    python3Packages.semantic-version
  ];
}
