{ stdenv
, gitRepos
, l4tMajorMinorPatchVersion
, buildPackages
, lib
, l4tOlder
, openssl
, opteeClient
, taDevKit
, l4tAtLeast
}:
stdenv.mkDerivation {
  pname = "optee_xtest";
  version = l4tMajorMinorPatchVersion;

  src = gitRepos."tegra/optee-src/nv-optee";
  patches = [ ./0001-GCC-15-compile-fix.patch ];

  nativeBuildInputs = [
    (buildPackages.python3.withPackages (p: [ p.cryptography ]))
  ] ++ lib.optionals (l4tOlder "36") [ openssl ];

  buildInputs = [ ] ++ lib.optionals (l4tOlder "36") [ openssl ];

  postPatch = ''
    patchShebangs --build $(find optee/optee_test -type d -name scripts -printf '%p ')
  '';
  makeFlags = [
    "-C optee/optee_test"
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
    "OPTEE_CLIENT_EXPORT=${opteeClient}"
    "TA_DEV_KIT_DIR=${taDevKit}/export-ta_arm64"
    "O=$(PWD)/out"
  ] ++ lib.optionals (l4tAtLeast "36") [
    "WITH_OPENSSL=n"
  ];
  installPhase = ''
    runHook preInstall

    install -Dm 755 ./out/xtest/xtest $out/bin/xtest
    find ./out -name "*.ta" -exec cp {} $out \;

    runHook postInstall
  '';
};
