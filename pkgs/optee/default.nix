{ l4tVersion
, bspSrc
, buildPackages
, lib
, stdenv
, fetchgit
, pkg-config
, libuuid
, dtc
, nukeReferences
, fetchpatch
}:

let
  atfSrc = fetchgit {
    url = "https://nv-tegra.nvidia.com/r/tegra/optee-src/atf";
    rev = "jetson_${l4tVersion}";
    sha256 = "sha256-9ml28qXN0B04ZocBr04x4tBzJ3iLgqGoVBveSkSCrgk=";
  };

  nvopteeSrc = fetchgit {
    url = "https://nv-tegra.nvidia.com/r/tegra/optee-src/nv-optee";
    rev = "jetson_${l4tVersion}";
    sha256 = "sha256-44RBXFNUlqZoq3OY/OFwhiU4Qxi4xQNmetFmlrr6jzY=";
  };

  opteeClient = stdenv.mkDerivation {
    pname = "optee_client";
    version = l4tVersion;
    src = nvopteeSrc;
    patches = [
      ./0001-Don-t-prepend-foo-bar-baz-to-TEEC_LOAD_PATH.patch
      (fetchpatch {
        name = "tee-supplicant-Allow-for-TA-load-path-to-be-specified-at-runtime.patch";
        url = "https://github.com/OP-TEE/optee_client/commit/f3845d8bee3645eedfcc494be4db034c3c69e9ab.patch";
        stripLen = 1;
        extraPrefix = "optee/optee_client/";
        hash = "sha256-XjFpMbyXy74sqnc8l+EgTaPXqwwHcvni1Z68ShokTGc=";
      })
    ];
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ libuuid ];
    makeFlags = [
      "-C optee/optee_client"
      "DESTDIR=$(out)"
      "SBINDIR=/sbin"
      "LIBDIR=/lib"
      "INCLUDEDIR=/include"
    ];
    meta.platforms = [ "aarch64-linux" ];
  };

  buildOptee = lib.makeOverridable ({ pname ? "optee-os"
                                    , socType
                                    , earlyTaPaths ? [ ]
                                    , extraMakeFlags ? [ ]
                                    , opteePatches ? [ ]
                                    , taPublicKeyFile ? null
                                    , ...
                                    }:
    let
      nvCccPrebuilt = {
        t194 = "";
        t234 = "${nvopteeSrc}/optee/optee_os/prebuilt/t234/libcommon_crypto.a";
      }.${socType};

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
      ++ (lib.optional (taPublicKeyFile != null) "TA_PUBLIC_KEY=${taPublicKeyFile}")
      ++ extraMakeFlags;
    in
    stdenv.mkDerivation {
      inherit pname;
      version = l4tVersion;
      src = nvopteeSrc;
      patches = opteePatches;
      postPatch = ''
        patchShebangs $(find optee/optee_os -type d -name scripts -printf '%p ')
      '';
      nativeBuildInputs = [
        dtc
        (buildPackages.python3.withPackages (p: with p; [ pyelftools cryptography ]))
      ];
      inherit makeFlags;
      # NOTE: EARLY_TA_PATHS needs to be added outside of `makeFlags` since it is a
      # space separated list of paths. See
      # https://nixos.org/manual/nixpkgs/stable/#build-phase for more details.
      preBuild = lib.optionalString (earlyTaPaths != [ ]) ''
        makeFlagsArray+=(EARLY_TA_PATHS="${toString earlyTaPaths}")
      '';
      dontInstall = true;
      meta.platforms = [ "aarch64-linux" ];
    });

  buildOpteeTaDevKit = args: buildOptee (args // {
    pname = "optee-ta-dev-kit";
    extraMakeFlags = (args.extraMakeFlags or [ ]) ++ [ "ta_dev_kit" ];
  });

  buildNvLuksSrv = args: stdenv.mkDerivation {
    pname = "nvluks-srv";
    version = l4tVersion;
    src = nvopteeSrc;
    patches = [ ./0001-nvoptee-no-install-makefile.patch ./0002-Exit-with-non-zero-status-code-on-TEEC_InvokeCommand.patch ];
    nativeBuildInputs = [ (buildPackages.python3.withPackages (p: [ p.cryptography ])) ];
    makeFlags = [
      "-C optee/samples/luks-srv"
      "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
      "TA_DEV_KIT_DIR=${buildOpteeTaDevKit args}/export-ta_arm64"
      "OPTEE_CLIENT_EXPORT=${opteeClient}"
      "O=$(PWD)/out"
    ];
    installPhase = ''
      runHook preInstall

      install -Dm755 -t $out/bin out/ca/luks-srv/nvluks-srv-app
      install -Dm755 -t $out out/early_ta/luks-srv/*.stripped.elf

      runHook postInstall
    '';
    meta.platforms = [ "aarch64-linux" ];
  };

  buildHwKeyAgent = args: stdenv.mkDerivation {
    pname = "hwkey-agent";
    version = l4tVersion;
    src = nvopteeSrc;
    patches = [ ./0001-nvoptee-no-install-makefile.patch ];
    nativeBuildInputs = [ (buildPackages.python3.withPackages (p: [ p.cryptography ])) ];
    makeFlags = [
      "-C optee/samples/hwkey-agent"
      "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
      "TA_DEV_KIT_DIR=${buildOpteeTaDevKit args}/export-ta_arm64"
      "OPTEE_CLIENT_EXPORT=${opteeClient}"
      "O=$(PWD)/out"
    ];
    installPhase = ''
      runHook preInstall

      install -Dm755 -t $out/bin out/ca/hwkey-agent/nvhwkey-app
      install -Dm755 -t $out out/ta/hwkey-agent/*.stripped.elf

      runHook postInstall
    '';
  };

  buildOpteeDTB = lib.makeOverridable ({ socType, ... }:
    let
      flavor = lib.replaceStrings [ "t" ] [ "" ] socType;
    in
    buildPackages.runCommand "tegra-${flavor}-optee.dtb"
      {
        nativeBuildInputs = [ dtc ];
      } ''
      mkdir -p $out
      dtc -I dts -O dtb -o $out/tegra${flavor}-optee.dtb ${nvopteeSrc}/optee/tegra${flavor}-optee.dts
    '');

  buildArmTrustedFirmware = lib.makeOverridable ({ socType, ... }:
    stdenv.mkDerivation {
      pname = "arm-trusted-firmware";
      version = l4tVersion;
      src = atfSrc;
      makeFlags = [
        "-C arm-trusted-firmware"
        "BUILD_BASE=$(PWD)/build"
        "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
        "DEBUG=0"
        "LOG_LEVEL=20"
        "PLAT=tegra"
        "SPD=opteed"
        "TARGET_SOC=${socType}"
        "V=0"
        # binutils 2.39 regression
        # `warning: /build/source/build/rk3399/release/bl31/bl31.elf has a LOAD segment with RWX permissions`
        # See also: https://developer.trustedfirmware.org/T996
        "LDFLAGS=-no-warn-rwx-segments"
      ];

      installPhase = ''
        runHook preInstall

        mkdir -p $out
        cp ./build/tegra/${socType}/release/bl31.bin $out/bl31.bin

        runHook postInstall
      '';

      meta.platforms = [ "aarch64-linux" ];
    });

  buildTOS = { socType, ... }@args:
    let
      armTrustedFirmware = buildArmTrustedFirmware args;

      opteeDTB = buildOpteeDTB args;

      nvLuksSrv = buildNvLuksSrv args;
      hwKeyAgent = buildHwKeyAgent args;

      opteeOS = buildOptee ({
        earlyTaPaths = [
          "${nvLuksSrv}/b83d14a8-7128-49df-9624-35f14f65ca6c.stripped.elf"
          "${hwKeyAgent}/82154947-c1bc-4bdf-b89d-04f93c0ea97c.stripped.elf"
        ];
      } // args);

      image = buildPackages.runCommand "tos.img"
        {
          nativeBuildInputs = [ nukeReferences ];
          passthru = { inherit nvLuksSrv hwKeyAgent; };
        } ''
        mkdir -p $out
        ${buildPackages.python3}/bin/python3 ${bspSrc}/nv_tegra/tos-scripts/gen_tos_part_img.py \
          --monitor ${armTrustedFirmware}/bl31.bin \
          --os ${opteeOS}/core/tee-raw.bin \
          --dtb ${opteeDTB}/*.dtb \
          --tostype optee \
          $out/tos.img

        # Get rid of any string references to source(s)
        nuke-refs $out/*
      '';
    in
    image;
in
{
  inherit buildTOS buildOpteeTaDevKit opteeClient;
}
