{ stdenv
, taDevKit
, opteeClient
, l4tMajorMinorPatchVersion
, buildPackages
, gitRepos
}:
stdenv.mkDerivation {
  pname = "nvluks-srv";
  version = l4tMajorMinorPatchVersion;
  src = gitRepos."tegra/optee-src/nv-optee";
  patches = [ ./0001-nvoptee-no-install-makefile.patch ./0002-Exit-with-non-zero-status-code-on-TEEC_InvokeCommand.patch ];
  nativeBuildInputs = [ (buildPackages.python3.withPackages (p: [ p.cryptography ])) ];
  enableParallelBuilding = true;
  makeFlags = [
    "-C optee/samples/luks-srv"
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
    "TA_DEV_KIT_DIR=${taDevKit}/export-ta_arm64"
    "OPTEE_CLIENT_EXPORT=${opteeClient}"
    "O=$(PWD)/out"
  ];
  installPhase = ''
    runHook preInstall

    install -Dm755 -t $out/bin out/ca/luks-srv/nvluks-srv-app
    install -Dm755 -t $out out/early_ta/luks-srv/*.stripped.elf

    runHook postInstall
  '';
  meta.platforms = [ "aarch64-linux" ];
}
