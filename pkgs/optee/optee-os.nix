{ buildPackages
, dtc
, gitRepos
, l4tMajorMinorPatchVersion
, lib
, stdenv
, uefi-firmware ? null
}:
stdenv.mkDerivation (finalAttrs:
let
  nvCccPrebuilt = {
    t194 = "";
    t234 = "${finalAttrs.src}/optee/optee_os/prebuilt/t234/libcommon_crypto.a";
    t264 = "${finalAttrs.src}/optee/optee_os/prebuilt/t264/libcommon_crypto.a";
  }.${finalAttrs.socType};

  l4tMajorVersion = lib.versions.major l4tMajorMinorPatchVersion;
in
{
  pname = "optee-os";
  version = l4tMajorMinorPatchVersion;

  # Override-able arguments
  earlyTaPaths = [ ];
  socType =
    if l4tMajorVersion == "35" then "t194"
    else if l4tMajorVersion == "36" then "t234"
    else if l4tMajorVersion == "38" then "t264"
    else throw "Unknown SoC type";
  coreLogLevel = 2;
  taLogLevel = finalAttrs.coreLogLevel;
  taPublicKeyFile = null;

  src = gitRepos."tegra/optee-src/nv-optee";
  patches = [ ./remove-force-log-level.diff ];

  nativeBuildInputs = [
    dtc
    (buildPackages.python3.withPackages (p: with p; [ pyelftools cryptography ]))
  ];

  enableParallelBuilding = true;

  postPatch = ''
    patchShebangs $(find optee/optee_os -type d -name scripts -printf '%p ')
  '';

  # NOTE: EARLY_TA_PATHS needs to be added outside of `makeFlags` since it is a
  # space separated list of paths. See
  # https://nixos.org/manual/nixpkgs/stable/#build-phase for more details.
  preBuild = lib.optionalString (finalAttrs.earlyTaPaths != [ ]) ''
    makeFlagsArray+=(EARLY_TA_PATHS="${toString finalAttrs.earlyTaPaths}")
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
  ++ (lib.optionals ((finalAttrs.socType == "t194" || finalAttrs.socType == "t234") && uefi-firmware != null) [
    "CFG_WITH_STMM_SP=y"
    "CFG_STMM_PATH=${uefi-firmware}/standalonemm_optee.bin"
  ])
  ++ (lib.optional (finalAttrs.taPublicKeyFile != null) "TA_PUBLIC_KEY=${finalAttrs.taPublicKeyFile}")
  ;

  dontInstall = true;

  meta.platforms = [ "aarch64-linux" ];
})
