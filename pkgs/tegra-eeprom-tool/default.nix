{ stdenv, lib, fetchFromGitHub, cmake, pkg-config, libedit }:

stdenv.mkDerivation rec {
  pname = "tegra-eeprom-tool";
  version = "unstable-2023-03-24";

  src = fetchFromGitHub {
    owner = "OE4T";
    repo = pname;
    rev = "283a701d25283a4e5584f5fe072bcb2d7d2ae1b1";
    sha256 = "sha256-YMHIruwF9YKjYJY52DLJ8eovFZYyrUt1jb5GbTcrC+A=";
  };

  nativeBuildInputs = [ cmake pkg-config ];
  buildInputs = [ libedit ];

  outputs = [ "bin" "out" "dev" ];

  meta = with lib; {
    description = "Tools for reading and writing identification EEPROMs on NVIDIA Jetson platforms";
    homepage = "https://github.com/OE4T/tegra-eeprom-tool";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
