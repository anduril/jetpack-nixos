{ opteeClient, python3 }:
python3.pkgs.buildPythonApplication {
  pname = "optee-gen-ekb";
  version = opteeClient.version;
  src = opteeClient.src;
  propagatedBuildInputs = with python3.pkgs; [
    cryptography
    pycryptodome
  ];
  format = "none";
  installPhase = ''
    mkdir -p $out/bin
    cp $src/optee/samples/hwkey-agent/host/tool/gen_ekb/gen_ekb.py $out/bin/optee-gen-ekb
  '';
}
