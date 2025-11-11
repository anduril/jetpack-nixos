{ lib
, stdenv
, callPackage
, buildPackages
, runCommand
, acpica-tools
, dtc
, unixtools
, libuuid
, which
, nasm
, applyPatches
, l4tMajorMinorPatchVersion
, uniqueHash ? ""
, # Optional path to a boot logo that will be converted and cropped into the format required
  bootLogo ? null
, # Patches to apply to edk2-nvidia source tree
  edk2NvidiaPatches ? [ ]
, # Patches to apply to edk2 source tree
  edk2UefiPatches ? [ ]
, debugMode ? false
  # Enables a bunch more info messages
, errorLevelInfo ? debugMode
  # The root certificate (in PEM format) for authenticating capsule updates. By
  # default, EDK2 authenticates using a test keypair commited upstream.
, trustedPublicCertPemFile ? null
, srcs
, ...
}:
let
  # TODO: Move this generation out of uefi-firmware.nix, because this .nix
  # file is callPackage'd using an aarch64 version of nixpkgs, and we don't
  # want to have to recompilie imagemagick
  bootLogoVariants = runCommand "uefi-bootlogo" { nativeBuildInputs = [ buildPackages.buildPackages.imagemagick ]; } ''
    mkdir -p "$out"
    convert "${bootLogo}" -resize 1920x1080 -gravity Center -extent 1920x1080 -format bmp -define bmp:format=bmp3 "$out/logo1080.bmp"
    convert "${bootLogo}" -resize 1280x720  -gravity Center -extent 1280x720  -format bmp -define bmp:format=bmp3 "$out/logo720.bmp"
    convert "${bootLogo}" -resize 640x480   -gravity Center -extent 640x480   -format bmp -define bmp:format=bmp3 "$out/logo480.bmp"
  '';

  patchedSrcs = srcs // {
    edk2-nvidia = applyPatches {
      name = "edk2-nvidia";
      src = srcs.edk2-nvidia;
      patches = edk2NvidiaPatches;
    };
  };

  pythonEnv = buildPackages.python312.withPackages (ps: callPackage ./pyenv.nix { inherit ps; inherit (patchedSrcs) edk2-nvidia; });

  buildTarget = if debugMode then "DEBUG" else "RELEASE";

  targetArch =
    if stdenv.hostPlatform.isi686 then
      "IA32"
    else if stdenv.hostPlatform.isx86_64 then
      "X64"
    else if stdenv.hostPlatform.isAarch32 then
      "ARM"
    else if stdenv.hostPlatform.isAarch64 then
      "AARCH64"
    else if stdenv.hostPlatform.isRiscV64 then
      "RISCV64"
    else if stdenv.hostPlatform.isLoongArch64 then
      "LOONGARCH64"
    else
      throw "Unsupported architecture";

in
{ platformBuild
, outputs
, stuartExtraArgs ? ""
}:
let
  _outputs = builtins.map (s: "Build/*/*/" + s) outputs;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "${platformBuild}-edk2-uefi-${buildTarget}";
  version = l4tMajorMinorPatchVersion;

  srcs = builtins.attrValues patchedSrcs;

  sourceRoot = ".";

  depsBuildBuild = [ buildPackages.stdenv.cc buildPackages.bash libuuid ];
  nativeBuildInputs = [
    pythonEnv

    # from nixpkgs, for stuart
    acpica-tools
    dtc
    nasm
    unixtools.whereis
    which
  ];
  strictDeps = true;

  env = {
    # NVIDIA's PrePI performs C function calls before stack has been set up.
    # https://github.com/NVIDIA/edk2-nvidia/blob/r38.2/Silicon/NVIDIA/Library/TegraPlatformInfoLib/AArch64/TegraPlatformInfo.S#L61
    # https://github.com/NVIDIA/edk2-nvidia/blob/r38.2/Silicon/NVIDIA/Library/TegraPlatformInfoLib/TegraPlatformInfoLib.c#L24
    # nixos/nixpkgs#399014 enables `-fno-omit-frame-pointer` by default which
    # causes PrePI to try to derefence uninitalized stack pointer.
    NIX_CFLAGS_COMPILE = "-fomit-frame-pointer";

    # stuart (nvidia extensions) really wants CROSS_COMPILER_PREFIX to look like this
    CROSS_COMPILER_PREFIX = "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}";
    # Version is ${FIRMWARE_VERSION_BASE}-${GIT_SYNC_REVISION}
    FIRMWARE_VERSION_BASE = "${l4tMajorMinorPatchVersion}";

    # Needed for Edk2ToolsBuild
    # trick taken from https://src.fedoraproject.org/rpms/edk2/blob/08f2354cd280b4ce5a7888aa85cf520e042955c3/f/edk2.spec#_319
    ${"GCC5_${targetArch}_PREFIX"} = stdenv.cc.targetPrefix;
    ${"GCC_${targetArch}_PREFIX"} = stdenv.cc.targetPrefix;
  };

  # see nixpkgs/pkgs/by-name/ed/edk2/package.nix
  hardeningDisable = [
    "format"
    "fortify"
  ];

  patches = edk2UefiPatches;

  patchPhase = ''
    find . -name \*_ext_dep.yaml -delete
    patchShebangs .
  '' + lib.optionalString errorLevelInfo ''
    sed -i 's#PcdDebugPrintErrorLevel|.*#PcdDebugPrintErrorLevel|0x8000004F#' edk2-nvidia/Platform/NVIDIA/NVIDIA.common.dsc.inc
  '' + lib.optionalString (bootLogo != null) ''
    cp ${bootLogoVariants}/logo1080.bmp edk2-nvidia/Silicon/NVIDIA/Drivers/Logo/nvidiagray1080.bmp
    cp ${bootLogoVariants}/logo720.bmp edk2-nvidia/Silicon/NVIDIA/Drivers/Logo/nvidiagray720.bmp
    cp ${bootLogoVariants}/logo480.bmp edk2-nvidia/Silicon/NVIDIA/Drivers/Logo/nvidiagray480.bmp
  '';

  configurePhase = ''
    runHook preConfigure

    export CC=$CC_FOR_BUILD
    export LD=$LD_FOR_BUILD
    export CPP=$CPP_FOR_BUILD
    export CXX=$CXX_FOR_BUILD
    export CFLAGS=$NIX_CFLAGS_COMPILE_FOR_BUILD
    export LDFLAGS=$NIX_LDFLAGS_FOR_BUILD

    export WORKSPACE=$(pwd)
    export GIT_SYNC_REVISION=$(printf "%s-%s" "${uniqueHash}" "$out" | sha256sum | head -c 12)
    python edk2/BaseTools/Edk2ToolsBuild.py -t GCC5
    # DANGER: If someone else modifies PYTHONPATH, then we lose this
    # We're okay when this was written.
    export PYTHONPATH=$(pwd)/edk2-nvidia/Silicon/NVIDIA

    ${lib.optionalString (trustedPublicCertPemFile != null) ''
    echo Using ${trustedPublicCertPemFile} as public certificate for capsule verification
    ${lib.getExe buildPackages.openssl} x509 -outform DER -in ${trustedPublicCertPemFile} -out edk2/PublicCapsuleKey.cer
    python3 edk2/BaseTools/Scripts/BinToPcd.py -p gEfiSecurityPkgTokenSpaceGuid.PcdPkcs7CertBuffer -i edk2/PublicCapsuleKey.cer -o edk2/PublicCapsuleKey.cer.gEfiSecurityPkgTokenSpaceGuid.PcdPkcs7CertBuffer.inc
    python3 edk2/BaseTools/Scripts/BinToPcd.py -x -p gFmpDevicePkgTokenSpaceGuid.PcdFmpDevicePkcs7CertBufferXdr -i edk2/PublicCapsuleKey.cer -o edk2/PublicCapsuleKey.cer.gFmpDevicePkgTokenSpaceGuid.PcdFmpDevicePkcs7CertBufferXdr.inc
    ''}

    runHook postConfigure
  '';

  buildPhase = ''
    stuart_setup -c "edk2-nvidia/Platform/NVIDIA/${platformBuild}/PlatformBuild.py"
    stuart_build -c "edk2-nvidia/Platform/NVIDIA/${platformBuild}/PlatformBuild.py" ${stuartExtraArgs} --target ${buildTarget}
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    # all-build-outputs and build log are helpful to have on hand when debugging issues
    find ./Build ./Conf > $out/all-build-outputs

    for file in Build/BUILDLOG_*.txt ${builtins.concatStringsSep " " _outputs} ; do
      mv -v $file $out/
    done

    runHook postInstall
  '';

  meta.platforms = [ "aarch64-linux" ];
})
