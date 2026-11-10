{ buildPackages
, dtc
, gitRepos
, l4tMajorMinorPatchVersion
, lib
, stdenv
, jetsonStandaloneMMOptee ? null
, socType ? if lib.versions.major l4tMajorMinorPatchVersion == "35" then "t194"
  else if lib.versions.major l4tMajorMinorPatchVersion == "36" then "t234"
  else if lib.versions.major l4tMajorMinorPatchVersion == "39" then "t264"
  else throw "Unknown SoC type"
, coreLogLevel ? 2
, taLogLevel ? null # null follows finalAttrs.coreLogLevel, including overrides
, taPublicKeyFile ? null
, enableFTPM ? false
, measuredBoot ? false
, unsecureInjectEPS ? false
, patches ? [ ]
, extraMakeFlags ? [ ]
}:
stdenv.mkDerivation (finalAttrs:
let
  nvCccPrebuilt = {
    t194 = "";
    t234 = "${finalAttrs.src}/optee/optee_os/prebuilt/t234/libcommon_crypto.a";
    t264 = "${finalAttrs.src}/optee/optee_os/prebuilt/t264/libcommon_crypto.a";
  }.${finalAttrs.socType};
in
{
  # Shared build config for optee-os and taDevKit. TA derivations and
  # earlyTaPaths live on optee-os instead, to avoid an
  # optee-config -> fTPM TA -> taDevKit -> optee-config cycle.
  pname = "optee-config";
  version = l4tMajorMinorPatchVersion;

  # Retain derivation attributes so overrideAttrs extensions still control flags.
  inherit socType coreLogLevel taPublicKeyFile enableFTPM measuredBoot unsecureInjectEPS;
  taLogLevel = if taLogLevel == null then finalAttrs.coreLogLevel else taLogLevel;

  src = gitRepos."tegra/optee-src/nv-optee";
  patches = [
    ./remove-force-log-level.diff
    ./0003-Add-pre-sign-hook.patch
  ] ++ lib.optionals (lib.versionAtLeast l4tMajorMinorPatchVersion "36") [
    ./0001-jetson_ftpm_helper_pta-Return-SHORT_BUFFER-when-EPS-.patch
  ] ++ patches;

  nativeBuildInputs = [
    dtc
    (buildPackages.python3.withPackages (p: with p; [ pyelftools cryptography ]))
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-Wno-incompatible-pointer-types"
  ];

  enableParallelBuilding = true;

  postPatch = ''
    patchShebangs $(find optee/optee_os -type d -name scripts -printf '%p ')
  '';

  makeFlags = [
    "-C optee/optee_os"
    "CROSS_COMPILE64=${stdenv.cc.targetPrefix}"
    "PLATFORM=tegra"
    "PLATFORM_FLAVOR=${finalAttrs.socType}"
    "NV_CCC_PREBUILT=${nvCccPrebuilt}"
    "O=$(out)"
    "CFG_TEE_CORE_LOG_LEVEL=${toString finalAttrs.coreLogLevel}"
    "CFG_TEE_TA_LOG_LEVEL=${toString finalAttrs.taLogLevel}"
  ]
  ++ (lib.optionals ((finalAttrs.socType == "t194" || finalAttrs.socType == "t234") && jetsonStandaloneMMOptee != null) [
    "CFG_WITH_STMM_SP=y"
    "CFG_STMM_PATH=${jetsonStandaloneMMOptee}/standalonemm_optee.bin"
  ])
  ++ (lib.optional (finalAttrs.taPublicKeyFile != null) "TA_PUBLIC_KEY=${finalAttrs.taPublicKeyFile}")
  ++ lib.optionals finalAttrs.enableFTPM ([
    "CFG_REE_STATE=y"
    "CFG_JETSON_FTPM_HELPER_PTA=y"
  ]
  ++ lib.optional finalAttrs.measuredBoot "CFG_CORE_TPM_EVENT_LOG=y"
  ++ lib.optional finalAttrs.unsecureInjectEPS
    (lib.warn
      "fTPM is using UNSECURE Endorsement Primary Seed (EPS) injection."
      "CFG_JETSON_FTPM_HELPER_INJECT_EPS=y"))
  ++ extraMakeFlags;

  dontInstall = true;

  meta.platforms = [ "aarch64-linux" ];
})
