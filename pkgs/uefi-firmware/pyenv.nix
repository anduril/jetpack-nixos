{ fetchFromGitHub
, ps
, ...
}:
with ps;
let
  edk2-pytool-library = buildPythonPackage
    rec {
      pname = "edk2-pytool-library";
      # Bumped from 0.19.3 for edk2-basetools
      version = "0.23.2";
      pyproject = true;

      src = fetchPypi {
        pname = "edk2_pytool_library";
        inherit version;
        hash = "sha256-v33XVI+m2CSOuuxsu2JcBjm0cQmspWQGireQzL6/6rI=";
      };
      build-system = [ setuptools-scm ];

      dependencies = [
        pyasn1
        pyasn1-modules
        cryptography
        joblib
        gitpython
        sqlalchemy
        pygount
      ];
    };
  edk2-pytool-extensions = buildPythonPackage
    rec {
      pname = "edk2-pytool-extensions";
      version = "0.29.4";
      pyproject = true;

      src = fetchPypi {
        pname = "edk2_pytool_extensions";
        inherit version;
        hash = "sha256-qHLLHjFKnfgn4aO6n+CxhEqwyR7MaHYOfZxJCDhR13s=";
      };
      build-system = [ setuptools-scm ];

      dependencies = [
        edk2-pytool-library
        pyyaml
        pefile
        semantic-version
        gitpython
        openpyxl
        xlsxwriter
      ];
    };
  edk2-basetools = buildPythonPackage
    rec {
      pname = "edk2-basetools";
      # Want 0.1.48, but it hard-codes a fetch from pypi!
      # 0.1.50 is broken, see tianocore/edk2-basetools#124
      version = "0.1.53";
      pyproject = true;

      src = fetchFromGitHub {
        owner = "tianocore";
        repo = pname;
        rev = "v${version}";
        hash = "sha256-qg54/2fYjX9pJbcu2iryrWIvQc1iOFl8v490zD7IhrA=";
      };
      build-system = [ setuptools setuptools-scm pytest pytest-html pytest-cov flake8 build ];

      dependencies = [
        edk2-pytool-library
        antlr4-python3-runtime
      ];
    };
  kconfiglib = buildPythonPackage
    rec {
      pname = "kconfiglib";
      version = "14.1.0"; # Latest when writing, conveniently not pinned
      pyproject = true;

      src = fetchPypi {
        inherit pname version;
        hash = "sha256-vtLMIhb1OOykJVqDpFiNiCNWPN1QEU+GzxomdOYCyTw=";
      };
      build-system = [ setuptools ];
    };
in
[
  # from edk2/pip-requirements.txt
  edk2-pytool-library
  edk2-pytool-extensions
  edk2-basetools
  antlr4-python3-runtime
  lcov-cobertura
  regex
  # from edk2-nvidia
  kconfiglib
  # implicit!
  setuptools
]
