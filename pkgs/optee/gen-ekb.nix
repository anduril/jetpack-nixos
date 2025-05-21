{ gitRepos, l4tMajorMinorPatchVersion, stdenv, python3 }:

stdenv.mkDerivation {
  pname = "gen_ekb.py";
  src = gitRepos."tegra/optee-src/nv-optee";
  version = l4tMajorMinorPatchVersion;
  dontBuild = true;
  buildInputs = [
    (python3.withPackages (p: with p; [
      cryptography
      pycryptodome
    ]))
  ];
  installPhase = ''
    runHook preInstall
    install -D optee/samples/hwkey-agent/host/tool/gen_ekb/gen_ekb.py \
      $out/bin/gen_ekb.py
    patchShebangs --host $out/bin/gen_ekb.py
    runHook postInstall
  '';
}
