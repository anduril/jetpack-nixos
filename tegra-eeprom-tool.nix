{ stdenv, lib, fetchFromGitHub, fetchpatch, cmake, pkg-config, libedit }:

stdenv.mkDerivation rec {
  pname = "tegra-eeprom-tool";
  version = "v2.0.1";

  src = fetchFromGitHub {
    owner = "OE4T";
    repo = pname;
    rev = version;
    sha256 = "sha256-H0BjgFLWf2eruyL5HF4Xu8IImiBra3qCofF4wfL1ebU=";
  };

  patches = [
    # Use CMAKE_INSTALL_FULL_* for absolute paths
    # https://github.com/OE4T/tegra-eeprom-tool/pull/8
    (fetchpatch {
      url = "https://github.com/danielfullmer/tegra-eeprom-tool/commit/25381fb3bd780f0e588744509edc17cf58003296.patch";
      sha256 = "sha256-QYcBglF6Ri0ZhJkVm4cIogkqbhm5e7tfDfWDim+IlhA=";
    })
    # Allow building using static libraries
    # https://github.com/OE4T/tegra-eeprom-tool/pull/9
    (fetchpatch {
      url = "https://github.com/danielfullmer/tegra-eeprom-tool/commit/e1b9349becb4ad5c28af19702d181751aa8ca52f.patch";
      sha256 = "sha256-BAQ0m9M+PAaiR+uaWXY4emClhpaxDOGyM1nKe8+F/FI=";
    })
  ];

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
