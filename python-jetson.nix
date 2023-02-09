{ python3, fetchFromGitHub }:

python3.pkgs.buildPythonPackage {
  pname = "python-jetson";
  version = "0.0.0";
  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "python-jetson";
    rev = "7cf586612820b8c81a17168541eb8bfc45b010de";
    sha256 = "sha256-APlDliwGqlhWChJESyCYyI2N9/yzlRdp1qwvfqlRjKM=";
  };

  propagatedBuildInputs = [ python3.pkgs.pyftdi ];

  doCheck = false;
}
