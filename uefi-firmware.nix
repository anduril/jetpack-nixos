{ lib, stdenv, buildPackages, fetchFromGitHub, runCommand, edk2, acpica-tools,
  dtc, python3, bc, imagemagick, applyPatches, nukeReferences,
  l4tVersion,

  # Optional path to a boot logo that will be converted and cropped into the format required
  bootLogo ? null,

  # Patches to apply to edk2-nvidia source tree
  edk2NvidiaPatches ? [],

  debugMode ? false,
  errorLevelInfo ? debugMode, # Enables a bunch more info messages
}:

let
  # TODO: Move this generation out of uefi-firmware.nix, because this .nix
  # file is callPackage'd using an aarch64 version of nixpkgs, and we don't
  # want to have to recompilie imagemagick
  bootLogoVariants = runCommand "uefi-bootlogo" { nativeBuildInputs = [ buildPackages.buildPackages.imagemagick ]; } ''
    mkdir -p $out
    convert ${bootLogo} -resize 1920x1080 -gravity Center -extent 1920x1080 -format bmp -define bmp:format=bmp3 $out/logo1080.bmp
    convert ${bootLogo} -resize 1280x720  -gravity Center -extent 1280x720  -format bmp -define bmp:format=bmp3 $out/logo720.bmp
    convert ${bootLogo} -resize 640x480   -gravity Center -extent 640x480   -format bmp -define bmp:format=bmp3 $out/logo480.bmp
  '';

  ###

  # See: https://github.com/NVIDIA/edk2-edkrepo-manifest/blob/main/edk2-nvidia/Jetson/NVIDIAJetsonManifest.xml
  edk2-src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2";
    rev = "r${l4tVersion}-edk2-stable202208";
    fetchSubmodules = true;
    sha256 = "sha256-PTbNxbncfSvxLW2XmdRHzUy+w5+1Blpk62DJpxDmedA=";
  };

  edk2-platforms = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-platforms";
    rev = "r${l4tVersion}-upstream-20220830";
    sha256 = "sha256-PjAJEbbswOLYupMg/xEqkAOJuAC8SxNsQlb9YBswRfo=";
  };

  edk2-non-osi = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-non-osi";
    rev = "r${l4tVersion}-upstream-20220830";
    sha256 = "sha256-EPtI63jYhEIo4uVTH3lUt9NC/lK5vPVacUAc5qgmz9M=";
  };

  _edk2-nvidia = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-nvidia";
    rev = "ad78b07af65d41bb96839f0bbe67bb445e04272f"; # Latest on r35.3.1-updates as of 2023-05-01
    sha256 = "sha256-PdrisHYkmBXGvfkNboVvKJnBqORiM8sUsGySj7n5Y5c=";
  };
  edk2-nvidia =
    if (errorLevelInfo || bootLogo != null)
    then applyPatches {
      src = _edk2-nvidia;
      patches = edk2NvidiaPatches;
      postPatch = lib.optionalString errorLevelInfo ''
        sed -i 's#PcdDebugPrintErrorLevel|.*#PcdDebugPrintErrorLevel|0x8000004F#' Platform/NVIDIA/NVIDIA.common.dsc.inc
      '' + lib.optionalString (bootLogo != null) ''
        cp ${bootLogoVariants}/logo1080.bmp Silicon/NVIDIA/Assets/nvidiagray1080.bmp
        cp ${bootLogoVariants}/logo720.bmp Silicon/NVIDIA/Assets/nvidiagray720.bmp
        cp ${bootLogoVariants}/logo480.bmp Silicon/NVIDIA/Assets/nvidiagray480.bmp
      '';
    }
    else _edk2-nvidia;

  edk2-nvidia-non-osi = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "edk2-nvidia-non-osi";
    rev = "r${l4tVersion}";
    sha256 = "sha256-27PTl+svZUocmU6r/8FdqqI9rwHAi+6zSFs4fBA13Ks=";
  };

  edk2-jetson = edk2.overrideAttrs (_: { src = edk2-src; });
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

  jetson-edk2-uefi =
    # TODO: edk2.mkDerivation doesn't have a way to override the edk version used!
    # Make it not via passthru ?
    stdenv.mkDerivation  {
      pname = "jetson-edk2-uefi";
      version = l4tVersion;

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
        cp -r ${edk2-jetson}/BaseTools BaseTools
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
          -D BUILDID_STRING=${l4tVersion} \
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

  uefi-firmware = runCommand "uefi-firmware-${l4tVersion}" {
    nativeBuildInputs = [ python3 nukeReferences ];
  } ''
    mkdir -p $out
    python3 ${edk2-nvidia}/Silicon/NVIDIA/Tools/FormatUefiBinary.py \
      ${jetson-edk2-uefi}/FV/UEFI_NS.Fv \
      $out/uefi_jetson.bin

    python3 ${edk2-nvidia}/Silicon/NVIDIA/Tools/FormatUefiBinary.py \
      ${jetson-edk2-uefi}/AARCH64/L4TLauncher.efi \
      $out/L4TLauncher.efi

    mkdir -p $out/dtbs
    for filename in ${jetson-edk2-uefi}/AARCH64/Silicon/NVIDIA/Tegra/DeviceTree/DeviceTree/OUTPUT/*.dtb; do
      cp $filename $out/dtbs/$(basename "$filename" ".dtb").dtbo
    done

    # Get rid of any string references to source(s)
    nuke-refs $out/uefi_jetson.bin
  '';
in {
  inherit edk2-jetson uefi-firmware;
}
