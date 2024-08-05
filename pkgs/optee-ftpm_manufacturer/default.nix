{ opteeClient
, stdenvNoCC
, python3
, fetchFromGitHub
, openssl
}:
let
  # Latest 1.5.1 release fails in x509.Name.build likely due
  # to PR270 and/or PR271. https://github.com/wbond/asn1crypto/pull/270
  asn1crypto' = python3.pkgs.asn1crypto.overrideAttrs (prev: {
    version = "unstable-git-20231103";
    src = fetchFromGitHub {
      owner = "wbond";
      repo = "asn1crypto";
      rev = "b763a757bb2bef2ab63620611ddd8006d5e9e4a2";
      hash = "sha256-11WajEDtisiJsKQjZMSd5sDog3DuuBzf1PcgSY+uuXY=";
    };
  });
in
stdenvNoCC.mkDerivation {
  pname = "optee-ftpm-manufacturer";
  version = opteeClient.version;
  src = opteeClient.src;
  pythonPath = with python3.pkgs; [
    asn1crypto' # use newer, pinned version
    cryptography
    ecdsa
    numpy
    oscrypto
    pyaes
    pycryptodome
    pycryptodomex
  ];
  nativeBuildInputs = [ python3.pkgs.wrapPython ];
  format = "none";
  installPhase = ''
    mkdir -p $out/bin $out/lib
    cp optee/samples/ftpm-helper/host/tool/ftpm_manufacturer_gen_ek_csr.sh $out/bin/optee-ftpm-manufacturer
    substituteInPlace $out/bin/optee-ftpm-manufacturer \
      --replace './ftpm_manufacturer_gen_ek_csr_tool.py' "$out/lib/ftpm_manufacturer_gen_ek_csr_tool.py"
    patchShebangs $out/bin/optee-ftpm-manufacturer
    cp optee/samples/ftpm-helper/host/tool/ftpm_manufacturer_gen_ek_csr_tool.py $out/lib/ftpm_manufacturer_gen_ek_csr_tool.py
    cp -r optee/samples/ftpm-helper/host/tool/lib $out/lib/lib
    wrapPythonProgramsIn "$out/lib" "$pythonPath"
  '';
  postFixup = ''
    wrapProgram $out/bin/optee-ftpm-manufacturer \
      --prefix PATH : ${openssl}/bin
  '';
}
