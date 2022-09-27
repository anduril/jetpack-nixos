{ lib, stdenv, buildPackages, fetchFromGitHub, runCommand, edk2, acpica-tools,
  dtc, python3, bc, applyPatches,

  # Optional path directory containing boot logos named logo1080.png, logo720.png, and logo480.png
  bootLogoVariants ? null,
}:

let
  version = "jetson-r35.1";

  debugMode = false;
  debugModeErrorLevelInfo = debugMode; # Enables a bunch more info messages

  ###

  # See: https://github.com/NVIDIA/edk2-edkrepo-manifest/blob/main/edk2-nvidia/Jetson/NVIDIAJetsonManifest.xml
  edk2-src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2";
    rev = version;
    fetchSubmodules = true;
    sha256 = "sha256-nm/Cx/DegFEvlJcm/9WMFeY9s7eSpahTLmD9KpJGqAo=";
  };

  edk2-platforms = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-platforms";
    rev = version;
    sha256 = "sha256-sbEddgJqByuKYIrLIgzqgpj7Qsy1wq0ACxHaSDqNbrc=";
  };

  edk2-non-osi = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-non-osi";
    rev = version;
    sha256 = "sha256-l8t+B4an/Ta6orfksoOTHOlr4bizTE7SXXKUankUgTg=";
  };

  _edk2-nvidia = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-nvidia";
    rev = version;
    sha256 = "sha256-hy1ph+bzBUGOTgp5DNicv/y2ORVxlcQgij53Z7p6C8Q=";
  };
  edk2-nvidia =
    if (debugModeErrorLevelInfo || bootLogoVariants != null)
    then applyPatches {
      src = _edk2-nvidia;
      postPatch = lib.optionalString debugModeErrorLevelInfo ''
        sed -i 's#PcdDebugPrintErrorLevel|.*#PcdDebugPrintErrorLevel|0x8000004F#' Platform/NVIDIA/NVIDIA.common.dsc.inc
      '' + lib.optionalString (bootLogoVariants != null) ''
        cp ${bootLogoVariants}/logo1080.bmp Silicon/NVIDIA/Assets/nvidiagray1080.bmp
        cp ${bootLogoVariants}/logo720.bmp Silicon/NVIDIA/Assets/nvidiagray720.bmp
        cp ${bootLogoVariants}/logo480.bmp Silicon/NVIDIA/Assets/nvidiagray480.bmp
      '';
    }
    else _edk2-nvidia;

  edk2-nvidia-non-osi = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-nvidia-non-osi";
    rev = version;
    sha256 = "sha256-hWTRlfCCdBoFZ4M2bJs8cwAKU2M2aDCPQj6uwvu8jso=";
  };

  my_edk2 = edk2.overrideAttrs (_: { src = edk2-src; });
  pythonEnv = buildPackages.python3.withPackages (ps: [ ps.tkinter ]);
  targetArch = if stdenv.isi686 then
    "IA32"
  else if stdenv.isx86_64 then
    "X64"
  else if stdenv.isAarch64 then
    "AARCH64"
  else
    throw "Unsupported architecture";

  buildType = if stdenv.isDarwin then
      "CLANGPDB"
    else
    "GCC5";

  buildTarget = if debugMode then "DEBUG" else "RELEASE";

  edk2-jetson =
    # TODO: edk2.mkDerivation doesn't have a way to override the edk version used!
    # Make it not via passthru ?
    stdenv.mkDerivation  {
      name = "edk2-jetson";
      inherit version;

      # Initialize the build dir with the build tools from edk2
      src = edk2-src;

      depsBuildBuild = [ buildPackages.stdenv.cc ];
      nativeBuildInputs = [ bc pythonEnv acpica-tools dtc ];
      strictDeps = true;

      NIX_CFLAGS_COMPILE = [ "-Wno-error=format-security" ];

      ${"GCC5_${targetArch}_PREFIX"} = stdenv.cc.targetPrefix;

      # From edk2-nvidia/Silicon/NVIDIA/edk2nv/stuart/settings.py
      PACKAGES_PATH = lib.concatStringsSep ":" [
        "${edk2-src}/BaseTools" # TODO: Is this needed?
        edk2-src edk2-platforms edk2-non-osi edk2-nvidia edk2-nvidia-non-osi
        "${edk2-platforms}/Features/Intel/OutOfBandManagement"
      ];

      enableParallelBuilding = true;

      prePatch = ''
        rm -rf BaseTools
        cp -r ${my_edk2}/BaseTools BaseTools
        chmod -R u+w BaseTools
      '';

      configurePhase = ''
        runHook preConfigure
        export WORKSPACE="$PWD"
        source ./edksetup.sh BaseTools
        runHook postConfigure
      '';

      buildPhase = ''
        runHook preBuild

        # The BUILDID_STRING and BUILD_DATE_TIME are used
        # just by nvidia, not generic edk2
        build -a ${targetArch} -b ${buildTarget} -t ${buildType} -p Platform/NVIDIA/Jetson/Jetson.dsc -n $NIX_BUILD_CORES \
          -D BUILDID_STRING=${version} \
          -D BUILD_DATE_TIME="$(date --utc --iso-8601=seconds --date=@$SOURCE_DATE_EPOCH)" \
          $buildFlags

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mv -v Build/*/* $out
        runHook postInstall
      '';
    };

    edk2-firmware = runCommand "jetson-firmware" { nativeBuildInputs = [ python3 ]; } ''
      mkdir -p $out
      python3 ${edk2-nvidia}/Silicon/NVIDIA/Tools/FormatUefiBinary.py \
        ${edk2-jetson}/FV/UEFI_NS.Fv \
        $out/uefi_jetson.bin

      python3 ${edk2-nvidia}/Silicon/NVIDIA/Tools/FormatUefiBinary.py \
        ${edk2-jetson}/AARCH64/L4TLauncher.efi \
        $out/L4TLauncher.efi

      mkdir -p $out/dtbs
      for filename in ${edk2-jetson}/AARCH64/Silicon/NVIDIA/Tegra/DeviceTree/DeviceTree/OUTPUT/*.dtb; do
        cp $filename $out/dtbs/$(basename "$filename" ".dtb").dtbo
      done
  '';
in {
  inherit edk2-jetson edk2-firmware;
}
