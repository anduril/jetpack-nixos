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
  pname = "nvluks-srv";
  version = l4tVersion;

  src = nvopteeSrc;

  patches = [ ./0001-nvoptee-no-install-makefile.patch ./0002-Exit-with-non-zero-status-code-on-TEEC_InvokeCommand.patch ];

  nativeBuildInputs = [ (buildPackages.python3.withPackages (p: [ p.cryptography ])) ];

  enableParallelBuilding = true;

  makeFlags = [
    "-C optee/samples/luks-srv"
    "CROSS_COMPILE=${opteeStdenv.cc.targetPrefix}"
    "TA_DEV_KIT_DIR=${opteeTaDevKit}/export-ta_arm64"
    "OPTEE_CLIENT_EXPORT=${opteeClient}"
    "O=$(PWD)/out"
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 -t $out/bin out/ca/luks-srv/nvluks-srv-app
    install -Dm755 -t $out out/early_ta/luks-srv/${finalAttrs.passthru.uuid}.stripped.elf

    runHook postInstall
  '';


  passthru.uuid = "b83d14a8-7128-49df-9624-35f14f65ca6c";

  meta = {
    platforms = [ "aarch64-linux" ];
    mainProgram = "nvluks-srv-app";
  };
})
