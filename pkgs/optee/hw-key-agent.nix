{ gitRepos
, opteeStdenv
, l4tVersion
, opteeTaDevKit
, opteeClient
, buildPackages
}:

let
  nvopteeSrc = gitRepos."tegra/optee-src/nv-optee";
in
opteeStdenv.mkDerivation (finalAttrs: {
  pname = "hwkey-agent";
  version = l4tVersion;

  src = nvopteeSrc;

  patches = [ ./0001-nvoptee-no-install-makefile.patch ];

  nativeBuildInputs = [ (buildPackages.python3.withPackages (p: [ p.cryptography ])) ];

  enableParallelBuilding = true;

  makeFlags = [
    "-C optee/samples/hwkey-agent"
    "CROSS_COMPILE=${opteeStdenv.cc.targetPrefix}"
    "TA_DEV_KIT_DIR=${opteeTaDevKit}/export-ta_arm64"
    "OPTEE_CLIENT_EXPORT=${opteeClient}"
    "O=$(PWD)/out"
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 -t $out/bin out/ca/hwkey-agent/nvhwkey-app
    install -Dm755 -t $out out/ta/hwkey-agent/${finalAttrs.passthru.uuid}.stripped.elf

    runHook postInstall
  '';


  passthru.uuid = "82154947-c1bc-4bdf-b89d-04f93c0ea97c";

  meta = {
    platforms = [ "aarch64-linux" ];
    mainProgram = "nvhwkey-app";
  };
})
