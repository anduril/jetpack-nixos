{ lib
, stdenv
, buildPackages
, fetchFromGitHub
, fetchurl
, fetchpatch
, fetchpatch2
, edk2
, acpica-tools
, dtc
, bc
, unixtools
, libuuid
, edk2NvidiaSrc

, debugMode ? false
  # The root certificate (in PEM format) for authenticating capsule updates. By
  # default, EDK2 authenticates using a test keypair commited upstream.
, trustedPublicCertPemFile ? null
, l4tVersion
}:
let
  # See: https://github.com/NVIDIA/edk2-edkrepo-manifest/blob/main/edk2-nvidia/Jetson/NVIDIAJetsonManifest.xml
  edk2Src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2";
    rev = "r${l4tVersion}-edk2-stable202208";
    fetchSubmodules = true;
    sha256 = "sha256-A4nICu2g4Kprdmb0KVfuo8d5I5P7nAri5bzB4j9vUb4=";
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
    sha256 = "sha256-h0EW5j5/pq0c48alz7w2+g4RCU2yQdYOtDiNFH9VI3M=";
  };

  # Patches from upstream tianocore/edk2 for OpenSSL, to enable in-tree build
  # of OpenSSL 1.1.1t
  opensslPatches = import ./edk2-openssl-patches.nix {
    inherit fetchpatch2;
  };

  # This has been taken from:
  # https://github.com/NixOS/nixpkgs/commit/3ed8d9b547c3941d74d9455fdec120f415ebaacd
  vendoredOpenSSL = fetchFromGitHub {
    owner = "openssl";
    repo = "openssl";
    rev = "OpenSSL_1_1_1t";
    sha256 = "sha256-gI2+Vm67j1+xLvzBb+DF0YFTOHW7myotRsXRzluzSLY=";
  };

  edk2-jetson = edk2.overrideAttrs (prev: {
    src = edk2Src;

    depsBuildBuild = prev.depsBuildBuild ++ [ libuuid ];

    patches =
      # Remove this one patch (CryptoPkg/OpensslLib: Upgrade OpenSSL to 1.1.1t)
      # present on nixos-23.05, as it will be added in the opensslPatches below
      (builtins.filter (patch: patch.url != "https://bugzilla.tianocore.org/attachment.cgi?id=1330") prev.patches)
      ++ opensslPatches;
    postUnpack = ''
      # This has been taken from:
      # https://github.com/NixOS/nixpkgs/commit/3ed8d9b547c3941d74d9455fdec120f415ebaacd
      rm -rf source/CryptoPkg/Library/OpensslLib/openssl
    '';
    postPatch = ''
      # This has been taken from:
      # https://github.com/NixOS/nixpkgs/commit/3ed8d9b547c3941d74d9455fdec120f415ebaacd

      # Replace the edk2's in-tree openssl git-submodule with our 1.1.1t
      cp -r ${vendoredOpenSSL} CryptoPkg/Library/OpensslLib/openssl
    '';
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
stdenv.mkDerivation {
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
    "${edk2Src}/BaseTools" # TODO: Is this needed?
    edk2Src
    edk2Platforms
    edk2NonOsi
    edk2NvidiaSrc
    edk2NvidiaNonOsi
    "${edk2Platforms}/Features/Intel/OutOfBandManagement"
  ];

  enableParallelBuilding = true;

  postUnpack = ''
    # This has been taken from:
    # https://github.com/NixOS/nixpkgs/commit/3ed8d9b547c3941d74d9455fdec120f415ebaacd
    rm -rf source/CryptoPkg/Library/OpensslLib/openssl
  '';

  prePatch = ''
    rm -rf BaseTools
    cp -r ${edk2-jetson}/BaseTools BaseTools
    chmod -R u+w BaseTools
  '';

  patches = opensslPatches ++ [
    (fetchurl {
      # Patch format does not play well with fetchpatch, it should be fine this is a static attachment in a ticket
      name = "CVE-2023-45229_CVE-2023-45230_CVE-2023-45231_CVE-2023-45232_CVE-2023-45233_CVE-2023-45234_CVE-2023-45235.patch";
      url = "https://bugzilla.tianocore.org/attachment.cgi?id=1457";
      hash = "sha256-CF41lbjnXbq/6DxMW6q1qcLJ8WAs+U0Rjci+jRwJYYY=";
    })
    (fetchpatch {
      name = "CVE-2022-36764.patch";
      url = "https://bugzilla.tianocore.org/attachment.cgi?id=1436";
      hash = "sha256-czku8DgElisDv6minI67nNt6BS+vH6txslZdqiGaQR4=";
      excludes = [
        "SecurityPkg/Test/SecurityPkgHostTest.dsc"
      ];
    })
  ];

  postPatch = ''
    # This has been taken from:
    # https://github.com/NixOS/nixpkgs/commit/3ed8d9b547c3941d74d9455fdec120f415ebaacd

    # Replace the edk2's in-tree openssl git-submodule with our 1.1.1t
    cp -r ${vendoredOpenSSL} CryptoPkg/Library/OpensslLib/openssl
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
}
