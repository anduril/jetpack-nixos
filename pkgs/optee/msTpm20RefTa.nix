{ stdenv
, taDevKit
, opteeClient
, l4tMajorMinorPatchVersion
, lib
, buildPackages
, gitRepos
}:
let
  l4tMajorVersion = lib.versions.major l4tMajorMinorPatchVersion;
  # r38 split NVIDIA's platform glue out of the in-tree MS reference TA at
  # optee/samples/ms-tpm-20-ref/Samples/ARM32-FirmwareTPM/optee_ta into a new
  # top-level optee/optee_ftpm/, and consumes the MS reference as a library
  # via CFG_MS_TPM_20_REF. The build output also moved from early_ta/ms-tpm/
  # to early_ta/optee_ftpm/. The OP-TEE TA UUID is the same on both
  # (bc50d971-d4c9-42c4-82cb-343fb7f37896), so consumers don't need to care.
  isR38OrLater = lib.versionAtLeast l4tMajorVersion "38";
in
stdenv.mkDerivation {
  pname = "ms-tpm-20-ref-ta";
  version = l4tMajorMinorPatchVersion;
  src = gitRepos."tegra/optee-src/nv-optee";
  nativeBuildInputs = [ (buildPackages.python3.withPackages (p: [ p.cryptography ])) ];
  enableParallelBuilding = true;

  # Suppress GCC 13+ warnings-as-errors. r36's ms-tpm-20-ref reference
  # sources trip these; r38's optee_ftpm/sub.mk already adds per-file
  # -Wno- flags, so this is belt-and-suspenders there.
  NIX_CFLAGS_COMPILE = "-Wno-incompatible-pointer-types -Wno-implicit-function-declaration";

  makeFlags = [
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
    "TA_DEV_KIT_DIR=${taDevKit}/export-ta_arm64"
    "OPTEE_CLIENT_EXPORT=${opteeClient}"
    "OPTEE_OS_DIR=$(PWD)/optee/optee_os"
    "CFG_USE_PLATFORM_EPS=y"
  ] ++ (if isR38OrLater then [
    "-C optee/optee_ftpm"
    "O=$(PWD)/out/early_ta/optee_ftpm"
    "CFG_MS_TPM_20_REF=$(PWD)/optee/samples/ms-tpm-20-ref"
  ] else [
    "-C optee/samples/ms-tpm-20-ref/Samples/ARM32-FirmwareTPM/optee_ta"
    "O=$(PWD)/out"
  ]);

  installPhase = ''
    runHook preInstall

    install -Dm755 -t $out out/early_ta/${if isR38OrLater then "optee_ftpm" else "ms-tpm"}/*.stripped.elf

    runHook postInstall
  '';
  meta.platforms = [ "aarch64-linux" ];
}
