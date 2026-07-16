{ buildPackages
, dtc
, gitRepos
, l4tMajorMinorPatchVersion
, lib
, stdenv
, jetsonStandaloneMMOptee ? null
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
  socType =
    if l4tMajorVersion == "35" then "t194"
    else if l4tMajorVersion == "36" then "t234"
    else if l4tMajorVersion == "39" then "t264"
    else throw "Unknown SoC type";
  coreLogLevel = 2;
  taLogLevel = finalAttrs.coreLogLevel;
  taPublicKeyFile = null;

  # fTPM — set ftpmHelperTa/msTpm20RefTa to the TA derivations to embed them as early TAs
  enableFTPM = false;
  measuredBoot = false;
  unsecureInjectEPS = false;
  ftpmHelperTa = null;
  msTpm20RefTa = null;

  # Stripped ELFs are used here rather than signed .ta files. Early TAs
  # are embedded directly in the OP-TEE binary image and do not require
  # signing — they inherit the same trust level as OP-TEE OS itself.
  # Only REE (file-system-loaded) TAs need to be signed.
  # See: https://optee.readthedocs.io/en/latest/building/trusted_applications.html#signing-of-tas
  #
  # Using enableFTPM (rather than ftpmHelperTa != null) ensures that if
  # enableFTPM = true but the TA paths weren't provided, you get an
  # immediate eval error instead of a silent disable of fTPM.
  earlyTaPaths = lib.optionals finalAttrs.enableFTPM [
    "${finalAttrs.ftpmHelperTa}/a6a3a74a-77cb-433a-990c-1dfb8a3fbc4c.stripped.elf"
    "${finalAttrs.msTpm20RefTa}/bc50d971-d4c9-42c4-82cb-343fb7f37896.stripped.elf"
  ];

  src = gitRepos."tegra/optee-src/nv-optee";
  patches = [
    ./remove-force-log-level.diff
    ./0003-Add-pre-sign-hook.patch
  ];

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
  ;

  dontInstall = true;

  meta.platforms = [ "aarch64-linux" ];
})
