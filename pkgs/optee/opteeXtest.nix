{ stdenv
, gitRepos
, nukeReferences
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

  # Multiple outputs: xtest binary, TAs, and plugins
  outputs = [
    "out"
    "tas"
    "plugins"
  ];


  nativeBuildInputs = [
    (buildPackages.python3.withPackages (p: [ p.cryptography ]))
    nukeReferences
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
    "TA_DIR=$(tas)" # xtest needs to manually load corrupt TA for test 1008
    "O=$(PWD)/out"
  ] ++ lib.optionals (l4tAtLeast "36") [
    "WITH_OPENSSL=n"
  ];
  installPhase = ''
    runHook preInstall

    install -Dm 755 ./out/xtest/xtest $out/bin/xtest

    find ./out -name "*.ta" -print0 | xargs -0 install -Dm 755 -t $tas
    find ./out -name "*.plugin" -print0 | xargs -0 install -Dm 755 -t $plugins

    runHook postInstall
  '';

  # We need to nuke-refs here because $tas/<uuid>.ta will retain a string
  # reference to $out/lib (and glibc/lib) on the nix-store. We need to break
  # this reference in order to split $out and $ta refs since $out/bin/xtest
  # refers to the $tas location for runtime loading.
  # The reason why the $out/lib reference is included in the TAs in the first
  # place is during the linking phase, some TAs can statically link to
  # eachother. This $out/lib path remains in the RPATH/RUNPATH for library
  # searching metadata. The existing objcopy --strip-unneeded does not strip
  # this unformation, despite it not being necessary for our TAs.
  preBuild =
    let
      taPreSign = ''
        cp \$input \$output
        nuke-refs \$output
      '';
    in
    ''
      cat > ta-pre-sign.sh <<EOF
      #!/bin/sh
      set -euo pipefail

      input="\$1"
      output="\$2"

      ${taPreSign}
      EOF
      chmod +x ta-pre-sign.sh
      makeFlagsArray+=(NIX_TA_PRE_SIGN_HOOK="$PWD/ta-pre-sign.sh")
    '';

}
