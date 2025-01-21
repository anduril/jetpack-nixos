{ lib
, stdenv
, buildPackages
, fetchFromGitHub
, edk2
, acpica-tools
, dtc
, bc
, unixtools
, libuuid
, edk2NvidiaSrc
, runCommand
, applyPatches
, fetchpatch

, debugMode ? false
  # The root certificate (in PEM format) for authenticating capsule updates. By
  # default, EDK2 authenticates using a test keypair commited upstream.
, trustedPublicCertPemFile ? null
, l4tVersion
}:
let
  # See: https://github.com/NVIDIA/edk2-edkrepo-manifest/blob/main/edk2-nvidia/Jetson/NVIDIAJetsonManifest.xml
  edk2Src = applyPatches {
    src = fetchFromGitHub {
      owner = "NVIDIA";
      repo = "edk2";
      rev = "r${l4tVersion}-edk2-stable202208";
      fetchSubmodules = true;
      sha256 = "sha256-w+rZq7Wjni62MJds6QmqpLod+zSFZ/qAN7kRDOit+jo=";
    };
    patches = [
      # Fix GCC 14 compile issue.
      # PR: https://github.com/tianocore/edk2/pull/5781
      (fetchpatch {
        url = "https://github.com/NVIDIA/edk2/commit/57a890fd03356350a1b7a2a0064c8118f44e9958.patch";
        hash = "sha256-on+yJOlH9B2cD1CS9b8Pmg99pzrlrZT6/n4qPHAbDcA=";
      })
    ];
  };

  edk2Platforms = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-platforms";
    rev = "r${l4tVersion}-upstream-20220830";
    sha256 = "sha256-PjAJEbbswOLYupMg/xEqkAOJuAC8SxNsQlb9YBswRfo=";
  };

  edk2NonOsi = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-non-osi";
    rev = "r${l4tVersion}-upstream-20220830";
    sha256 = "sha256-EPtI63jYhEIo4uVTH3lUt9NC/lK5vPVacUAc5qgmz9M=";
  };

  edk2NvidiaNonOsi = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-nvidia-non-osi";
    rev = "r${l4tVersion}";
    sha256 = "sha256-Fg8s9Fjwt5IzrGdJ7TKI3AjZLh/wHN8oyvi5Xw+Jg+k=";
  };

  edk2-jetson = edk2.overrideAttrs (prev: {
    # Upstream nixpkgs patch to use nixpkgs OpenSSL
    # See https://github.com/NixOS/nixpkgs/blob/44733514b72e732bd49f5511bd0203dea9b9a434/pkgs/development/compilers/edk2/default.nix#L57
    src = runCommand "edk2-unvendored-src" { } ''
      cp --no-preserve=mode -r ${edk2Src} $out
      rm -rf $out/CryptoPkg/Library/OpensslLib/openssl
      mkdir -p $out/CryptoPkg/Library/OpensslLib/openssl
      tar --strip-components=1 -xf ${buildPackages.openssl.src} -C $out/CryptoPkg/Library/OpensslLib/openssl
      chmod -R +w $out/
      # Fix missing INT64_MAX include that edk2 explicitly does not provide
      # via it's own <stdint.h>. Let's pull in openssl's definition instead:
      sed -i $out/CryptoPkg/Library/OpensslLib/openssl/crypto/property/property_parse.c \
          -e '1i #include "internal/numbers.h"'
    '';

    depsBuildBuild = prev.depsBuildBuild ++ [ libuuid ];
  });

  pythonEnv = buildPackages.python3.withPackages (ps: [ ps.tkinter ]);
  targetArch =
    if stdenv.isi686 then
      "IA32"
    else if stdenv.isx86_64 then
      "X64"
    else if stdenv.isAarch64 then
      "AARCH64"
    else
      throw "Unsupported architecture";

  buildType =
    if stdenv.isDarwin then
      "CLANGPDB"
    else
      "GCC5";

  buildTarget = if debugMode then "DEBUG" else "RELEASE";
in
# TODO: edk2.mkDerivation doesn't have a way to override the edk version used!
  # Make it not via passthru ?
stdenv.mkDerivation (finalAttrs: {
  pname = "jetson-edk2-uefi";
  version = l4tVersion;

  # Initialize the build dir with the build tools from edk2
  src = edk2Src;

  depsBuildBuild = [ buildPackages.stdenv.cc ];
  nativeBuildInputs = [ bc pythonEnv acpica-tools dtc unixtools.whereis ];
  strictDeps = true;

  NIX_CFLAGS_COMPILE = [
    "-Wno-error=format-security" # TODO: Fix underlying issue

    # Workaround for ../Silicon/NVIDIA/Drivers/EqosDeviceDxe/nvethernetrm/osi/core/osi_hal.c:1428: undefined reference to `__aarch64_ldadd4_sync'
    "-mno-outline-atomics"
  ];

  ${"GCC5_${targetArch}_PREFIX"} = stdenv.cc.targetPrefix;

  # From edk2-nvidia/Silicon/NVIDIA/edk2nv/stuart/settings.py
  PACKAGES_PATH = lib.concatStringsSep ":" [
    "${finalAttrs.src}/BaseTools" # TODO: Is this needed?
    finalAttrs.src
    edk2Platforms
    edk2NonOsi
    edk2NvidiaSrc
    edk2NvidiaNonOsi
    "${edk2Platforms}/Features/Intel/OutOfBandManagement"
  ];

  enableParallelBuilding = true;

  prePatch = ''
    rm -rf BaseTools
    cp -r ${edk2-jetson}/BaseTools BaseTools
    chmod -R u+w BaseTools
  '';

  configurePhase = ''
    runHook preConfigure
    export WORKSPACE="$PWD"
    source ./edksetup.sh BaseTools

    ${lib.optionalString (trustedPublicCertPemFile != null) ''
    echo Using ${trustedPublicCertPemFile} as public certificate for capsule verification
    ${lib.getExe buildPackages.openssl} x509 -outform DER -in ${trustedPublicCertPemFile} -out PublicCapsuleKey.cer
    python3 BaseTools/Scripts/BinToPcd.py -p gEfiSecurityPkgTokenSpaceGuid.PcdPkcs7CertBuffer -i PublicCapsuleKey.cer -o PublicCapsuleKey.cer.gEfiSecurityPkgTokenSpaceGuid.PcdPkcs7CertBuffer.inc
    python3 BaseTools/Scripts/BinToPcd.py -x -p gFmpDevicePkgTokenSpaceGuid.PcdFmpDevicePkcs7CertBufferXdr -i PublicCapsuleKey.cer -o PublicCapsuleKey.cer.gFmpDevicePkgTokenSpaceGuid.PcdFmpDevicePkcs7CertBufferXdr.inc
    ''}

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    # The BUILDID_STRING and BUILD_DATE_TIME are used
    # just by nvidia, not generic edk2
    build -a ${targetArch} -b ${buildTarget} -t ${buildType} -p Platform/NVIDIA/Jetson/Jetson.dsc -n $NIX_BUILD_CORES \
      -D BUILDID_STRING=${l4tVersion} \
      -D BUILD_DATE_TIME="$(date --utc --iso-8601=seconds --date=@$SOURCE_DATE_EPOCH)" \
      ${lib.optionalString (trustedPublicCertPemFile != null) "-D CUSTOM_CAPSULE_CERT"} \
      $buildFlags

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mv -v Build/*/* $out
    runHook postInstall
  '';
})
