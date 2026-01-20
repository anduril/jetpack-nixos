{ l4tMajorMinorPatchVersion
, l4tAtLeast
, l4tOlder
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
, gitRepos
, uefi-firmware
, openssl
}:

let
  atfSrc = gitRepos."tegra/optee-src/atf";
  nvopteeSrc = gitRepos."tegra/optee-src/nv-optee";

  opteeClient = stdenv.mkDerivation {
    pname = "optee_client";
    version = l4tMajorMinorPatchVersion;
    src = nvopteeSrc;
    patches =
      if l4tAtLeast "36" then [ ] else [
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
    enableParallelBuilding = true;
    makeFlags = [
      "-C optee/optee_client"
      "DESTDIR=$(out)"
      "SBINDIR=/sbin"
      "LIBDIR=/lib"
      "INCLUDEDIR=/include"
    ];
    meta.platforms = [ "aarch64-linux" ];
  };

  buildOpteeXtest = args: stdenv.mkDerivation {
    pname = "optee_xtest";
    version = l4tMajorMinorPatchVersion;
    src = nvopteeSrc;
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
      "TA_DEV_KIT_DIR=${buildOpteeTaDevKit args}/export-ta_arm64"
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

  buildPkcs11Ta = args: stdenv.mkDerivation {
    pname = "pkcs11ta";
    version = l4tMajorMinorPatchVersion;
    dontUnpack = true;
    installPhase = ''
      runHook preInstall

      mkdir $out
      install -Dm 755 ${buildOptee args}/ta/pkcs11/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta $out

      runHook postInstall
    '';
  };

  buildOptee = lib.makeOverridable ({ pname ? "optee-os"
                                    , socType
                                    , earlyTaPaths ? [ ]
                                    , extraMakeFlags ? [ ]
                                    , opteePatches ? [ ]
                                    , taPublicKeyFile ? null
                                    , coreLogLevel ? 2
                                    , taLogLevel ? coreLogLevel
                                    , ...
                                    }:
    let
      nvCccPrebuilt = {
        t194 = "";
        t234 = "${nvopteeSrc}/optee/optee_os/prebuilt/t234/libcommon_crypto.a";
        t264 = "${nvopteeSrc}/optee/optee_os/prebuilt/t264/libcommon_crypto.a";
      }.${socType};

      makeFlags = [
        "-C optee/optee_os"
        "CROSS_COMPILE64=${stdenv.cc.targetPrefix}"
        "PLATFORM=tegra"
        "PLATFORM_FLAVOR=${socType}"
        "NV_CCC_PREBUILT=${nvCccPrebuilt}"
        "O=$(out)"
        "CFG_TEE_CORE_LOG_LEVEL=${toString coreLogLevel}"
        "CFG_TEE_TA_LOG_LEVEL=${toString taLogLevel}"
      ]
      ++ (lib.optionals ((socType == "t194" || socType == "t234") && uefi-firmware != null) [
        "CFG_WITH_STMM_SP=y"
        "CFG_STMM_PATH=${uefi-firmware}/standalonemm_optee.bin"
      ])
      ++ (lib.optional (taPublicKeyFile != null) "TA_PUBLIC_KEY=${taPublicKeyFile}")
      ++ extraMakeFlags;
    in
    stdenv.mkDerivation {
      inherit pname;
      version = l4tMajorMinorPatchVersion;
      src = nvopteeSrc;
      patches = opteePatches ++ [ ./remove-force-log-level.diff ];
      postPatch = ''
        patchShebangs $(find optee/optee_os -type d -name scripts -printf '%p ')
      '';
      nativeBuildInputs = [
        dtc
        (buildPackages.python3.withPackages (p: with p; [ pyelftools cryptography ]))
      ];
      inherit makeFlags;
      enableParallelBuilding = true;
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
    version = l4tMajorMinorPatchVersion;
    src = nvopteeSrc;
    patches = [ ./0001-nvoptee-no-install-makefile.patch ./0002-Exit-with-non-zero-status-code-on-TEEC_InvokeCommand.patch ];
    nativeBuildInputs = [ (buildPackages.python3.withPackages (p: [ p.cryptography ])) ];
    enableParallelBuilding = true;
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

  buildCpuBlPayloadDec = args: stdenv.mkDerivation {
    pname = "cpubl-payload-dec";
    version = l4tMajorMinorPatchVersion;
    src = nvopteeSrc;
    patches = [ ./0001-nvoptee-no-install-makefile.patch ];
    nativeBuildInputs = [ (buildPackages.python3.withPackages (p: [ p.cryptography ])) ];
    enableParallelBuilding = true;
    makeFlags = [
      "-C optee/samples/cpubl-payload-dec"
      "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
      "TA_DEV_KIT_DIR=${buildOpteeTaDevKit args}/export-ta_arm64"
      "OPTEE_CLIENT_EXPORT=${opteeClient}"
      "O=$(PWD)/out"
    ];
    installPhase = ''
      runHook preInstall

      install -Dm755 -t $out out/early_ta/cpubl-payload-dec/*.stripped.elf

      runHook postInstall
    '';
    meta.platforms = [ "aarch64-linux" ];
  };

  buildHwKeyAgent = args: stdenv.mkDerivation {
    pname = "hwkey-agent";
    version = l4tMajorMinorPatchVersion;
    src = nvopteeSrc;
    patches = [ ./0001-nvoptee-no-install-makefile.patch ];
    nativeBuildInputs = [ (buildPackages.python3.withPackages (p: [ p.cryptography ])) ];
    enableParallelBuilding = true;
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
    let
      socSpecialization = gitRepos ? "tegra/optee-src/atf_${socType}";
      src = if socSpecialization then gitRepos."tegra/optee-src/atf_${socType}" else gitRepos."tegra/optee-src/atf";
      srcDir = if socSpecialization then "arm-trusted-firmware.${socType}" else "arm-trusted-firmware";
    in
    stdenv.mkDerivation {
      pname = "arm-trusted-firmware";
      version = l4tMajorMinorPatchVersion;
      inherit src;
      makeFlags = [
        "-C ${srcDir}"
        "BUILD_BASE=$(PWD)/build"
        "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
        "DEBUG=0"
        "LOG_LEVEL=20"
        "PLAT=tegra"
        "TARGET_SOC=${socType}"
        "V=0"
        # binutils 2.39 regression
        # `warning: /build/source/build/rk3399/release/bl31/bl31.elf has a LOAD segment with RWX permissions`
        # See also: https://developer.trustedfirmware.org/T996
        "LDFLAGS=-no-warn-rwx-segments"
        "OPENSSL_DIR=${lib.getLib buildPackages.openssl}"
      ] ++ lib.optionals (socType == "t194" || socType == "t234") [
        "SPD=opteed"
      ] ++ lib.optionals (socType == "t264") [
        "ARM_ARCH_MINOR=6"
        "CTX_INCLUDE_EL2_REGS=1"
        "SPD=spmd"
        "SP_LAYOUT_FILE=${src}/${srcDir}/secure_partition/sp_layout.json"
      ] ++ lib.optionals ((lib.versions.major l4tMajorMinorPatchVersion) == "36" && socType != "t194") [
        "BRANCH_PROTECTION=3"
        "ARM_ARCH_MINOR=3"
      ];

      buildFlags = [ "all" ] ++ lib.optional (l4tAtLeast "38") "fiptool";

      # openssl is used to build fiptool
      buildInputs = lib.optionals (l4tAtLeast "38") [ openssl ];
      nativeBuildInputs = lib.optionals (l4tAtLeast "38") [ dtc openssl buildPackages.stdenv.cc pkg-config ];

      strictDeps = true;
      enableParallelBuilding = true;

      installPhase = ''
        runHook preInstall

        mkdir -p $out
        cp ./build/tegra/${socType}/release/bl31.bin $out/bl31.bin

        ${lib.optionalString socSpecialization ''
          # From public sources, see instructions in nvidia-jetson-optee-source.tbz2
          dtc -I dts -O dtb -o nvidia-${socType}.dtb ${srcDir}/fdts/nvidia-${socType}.dts
          ${srcDir}/tools/fiptool/fiptool create --soc-fw $out/bl31.bin --soc-fw-config nvidia-${socType}.dtb $out/bl31.fip
        ''}


        runHook postInstall
      '';

      meta.platforms = [ "aarch64-linux" ];
    });

  buildTOS = { socType, ... }@args:
    let
      armTrustedFirmware = buildArmTrustedFirmware args;

      opteeDTB = buildOpteeDTB args;

      nvLuksSrv = buildNvLuksSrv args;
      cpuBlPayloadDec = buildCpuBlPayloadDec args;
      hwKeyAgent = buildHwKeyAgent args;

      opteeOS = buildOptee ({
        earlyTaPaths = lib.optionals (socType == "t194" || socType == "t234") [
          "${nvLuksSrv}/b83d14a8-7128-49df-9624-35f14f65ca6c.stripped.elf"
          "${cpuBlPayloadDec}/0e35e2c9-b329-4ad9-a2f5-8ca9bbbd7713.stripped.elf"
          "${hwKeyAgent}/82154947-c1bc-4bdf-b89d-04f93c0ea97c.stripped.elf"
        ];
      } // args);

      teeRaw = "${opteeOS}/core/tee-raw.bin";
      dtb = "${opteeDTB}/tegra${lib.removePrefix "t" socType}-optee.dtb";

      image = buildPackages.runCommand "tos.img"
        {
          nativeBuildInputs = [ nukeReferences ];
          passthru = { inherit nvLuksSrv hwKeyAgent; };
        } ''
        mkdir -p $out
        ${buildPackages.python3}/bin/python3 ${bspSrc}/nv_tegra/tos-scripts/gen_tos_part_img.py \
          --monitor ${armTrustedFirmware}/bl31.bin \
          --os ${teeRaw} \
          --dtb ${dtb} \
          --tostype optee \
          $out/tos.img

        # Get rid of any string references to source(s)
        nuke-refs $out/*
      '';

      imageSpTool = buildPackages.runCommand "tos.img"
        {
          nativeBuildInputs = [ nukeReferences ];
          passthru = { inherit nvLuksSrv hwKeyAgent; };
        } ''
        # From public sources, see instructions in nvidia-jetson-optee-source.tbz2
        mkdir -p $out
        ${lib.getExe buildPackages.python3} ${armTrustedFirmware.src}/arm-trusted-firmware.${socType}/tools/sptool/sptool.py \
          -i ${teeRaw}:${dtb} \
          -o $out/tos.img

        cp ${armTrustedFirmware}/bl31.fip $out/

        nuke-refs $out/*
      '';
    in
    {
      t194 = image;
      t234 = image;
      t264 = imageSpTool;
    }.${socType};
in
{
  inherit buildTOS buildOpteeTaDevKit opteeClient buildPkcs11Ta buildOpteeXtest;
}
