{ buildPackages
, gitRepos
, l4tAtLeast
, lib
, l4tMajorMinorPatchVersion
, stdenv
}:
stdenv.mkDerivation (finalAttrs:
let
  socSpecialization = gitRepos ? "tegra/optee-src/atf_${finalAttrs.socType}";
  src = if socSpecialization then gitRepos."tegra/optee-src/atf_${finalAttrs.socType}" else gitRepos."tegra/optee-src/atf";
  srcDir = if (l4tAtLeast "38") then "arm-trusted-firmware.${finalAttrs.socType}" else "arm-trusted-firmware";

  l4tMajorVersion = lib.versions.major l4tMajorMinorPatchVersion;
in
{
  name = "fiptool";
  version = l4tMajorMinorPatchVersion;

  src = src;

  socType =
    if l4tMajorVersion == "35" then "t194"
    else if l4tMajorVersion == "36" then "t234"
    else if l4tMajorVersion == "39" then "t264"
    else throw "Unknown SoC type";

  # openssl is used to build fiptool
  buildInputs = with buildPackages; lib.optionals (l4tAtLeast "38") [ openssl ];
  nativeBuildInputs = with buildPackages; lib.optionals (l4tAtLeast "38") [ dtc openssl buildPackages.stdenv.cc pkg-config ];

  strictDeps = true;
  enableParallelBuilding = true;

  makeFlags = [
    "-C ${srcDir}/tools/fiptool"
    "OPENSSL_DIR=${lib.getLib buildPackages.openssl}"
    "CC=${stdenv.cc.targetPrefix}cc"
    "LD=${stdenv.cc.targetPrefix}cc"
    "AS=${stdenv.cc.targetPrefix}cc"
    "OC=${stdenv.cc.targetPrefix}objcopy"
    "OD=${stdenv.cc.targetPrefix}objdump"
  ];

  buildFlags = [ "all" ] ++ lib.optional (l4tAtLeast "38") "fiptool";

  installPhase = ''
    runHook preInstall

    install -Dm 555 ${srcDir}/tools/fiptool/fiptool $out/bin/fiptool

    runHook postInstall
  '';
})
