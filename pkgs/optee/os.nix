{ lib
, gitRepos
, l4tVersion
, dtc
, buildPackages
, stdenv
, bspSrc
, socType
, earlyTaPaths ? [ ]
, taPublicKeyFile ? null
}:

let
  nvopteeSrc = gitRepos."tegra/optee-src/nv-optee";

  nvCccPrebuilt = {
    t194 = "";
    t234 = "${nvopteeSrc}/optee/optee_os/prebuilt/t234/libcommon_crypto.a";
  }.${socType};
in
stdenv.mkDerivation {
  pname = "optee-os";
  version = l4tVersion;

  src = nvopteeSrc;

  postPatch = ''
    patchShebangs $(find optee/optee_os -type d -name scripts -printf '%p ')
  '';

  nativeBuildInputs = [
    dtc
    (buildPackages.python3.withPackages (p: with p; [ pyelftools cryptography ]))
  ];

  makeFlags = [
    "-C optee/optee_os"
    "CROSS_COMPILE64=${stdenv.cc.targetPrefix}"
    "PLATFORM=tegra"
    "PLATFORM_FLAVOR=${socType}"
    "CFG_WITH_STMM_SP=y"
    "CFG_STMM_PATH=${bspSrc}/bootloader/standalonemm_optee_${socType}.bin"
    "NV_CCC_PREBUILT=${nvCccPrebuilt}"
    "O=$(out)"
  ]
  ++ (lib.optional (taPublicKeyFile != null) "TA_PUBLIC_KEY=${taPublicKeyFile}");

  enableParallelBuilding = true;

  # NOTE: EARLY_TA_PATHS needs to be added outside of `makeFlags` since it is a
  # space separated list of paths. See
  # https://nixos.org/manual/nixpkgs/stable/#build-phase for more details.
  preBuild = lib.optionalString (earlyTaPaths != [ ]) ''
    makeFlagsArray+=(EARLY_TA_PATHS="${toString earlyTaPaths}")
  '';

  dontInstall = true;

  meta.platforms = [ "aarch64-linux" ];
}
