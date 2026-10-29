{ stdenv, lib, fetchFromGitHub, cmake, pkg-config, libedit }:

stdenv.mkDerivation rec {
  pname = "tegra-eeprom-tool";
  version = "2.1.0";

  src = fetchFromGitHub {
    owner = "OE4T";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-oPc1IUyje4m9KDmvkyJbrImf5o/g+4eEkD6+e5Cq6iA=";
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
