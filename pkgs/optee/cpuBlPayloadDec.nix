{ stdenv
, taDevKit
, opteeClient
, l4tMajorMinorPatchVersion
, buildPackages
, gitRepos
}:
stdenv.mkDerivation {
  pname = "cpubl-payload-dec";
  version = l4tMajorMinorPatchVersion;
  src = gitRepos."tegra/optee-src/nv-optee";
  patches = [ ./0001-nvoptee-no-install-makefile.patch ];
  nativeBuildInputs = [ (buildPackages.python3.withPackages (p: [ p.cryptography ])) ];
  enableParallelBuilding = true;
  makeFlags = [
    "-C optee/samples/cpubl-payload-dec"
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
    "TA_DEV_KIT_DIR=${taDevKit}/export-ta_arm64"
    "OPTEE_CLIENT_EXPORT=${opteeClient}"
    "O=$(PWD)/out"
  ];
  installPhase = ''
    runHook preInstall

    install -Dm755 -t $out out/early_ta/cpubl-payload-dec/*.stripped.elf

    runHook postInstall
  '';
  meta.platforms = [ "aarch64-linux" ];
}
