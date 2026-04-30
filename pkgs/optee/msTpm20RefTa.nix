{ stdenv
, taDevKit
, opteeClient
, l4tMajorMinorPatchVersion
, buildPackages
, gitRepos
}:
# TODO: r38 refactored fTPM compilation to use the CFG_MS_TPM_20_REF flag in
# the optee-os build itself, which would make this separate TA derivation
# obsolete on r38. Add an r38 code path here (or replace this with the
# optee-os flag) once r38 fTPM support is wired up.
stdenv.mkDerivation {
  pname = "ms-tpm-20-ref-ta";
  version = l4tMajorMinorPatchVersion;
  src = gitRepos."tegra/optee-src/nv-optee";
  nativeBuildInputs = [ (buildPackages.python3.withPackages (p: [ p.cryptography ])) ];
  enableParallelBuilding = true;

  # Suppress GCC 13+ warnings-as-errors from upstream sources to avoid
  # depending on gcc13.
  NIX_CFLAGS_COMPILE = "-Wno-incompatible-pointer-types -Wno-implicit-function-declaration";

  makeFlags = [
    "-C optee/samples/ms-tpm-20-ref/Samples/ARM32-FirmwareTPM/optee_ta"
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
    "TA_DEV_KIT_DIR=${taDevKit}/export-ta_arm64"
    "OPTEE_CLIENT_EXPORT=${opteeClient}"
    "OPTEE_OS_DIR=$(PWD)/optee/optee_os"
    "O=$(PWD)/out"
    "CFG_USE_PLATFORM_EPS=y"
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 -t $out out/early_ta/ms-tpm/*.stripped.elf

    runHook postInstall
  '';
  meta.platforms = [ "aarch64-linux" ];
}
