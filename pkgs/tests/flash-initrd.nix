{ lib, runCommand, coreutils, findutils, glibcLocales, bash, writeText }:
let
  initrdConfig = compressor: prepend: {
    boot.initrd = { inherit compressor prepend; };
  };
  mkInitrd = signedFirmware: compressor: prepend: import ../../device-pkgs/flash-initrd {
    inherit signedFirmware;
    extraModules = [ ];
    flashFromDevice = "/unused/flash-from-device";
    pkgs.lib = lib;
    pkgs.nixos = modules: {
      config = initrdConfig compressor prepend;
      initialRamdisk.overrideAttrs = update:
        let
          system = (builtins.head modules) {
            config = initrdConfig compressor prepend;
            inherit lib;
            pkgs = { };
            utils = { };
          };
          original = {
            outPath = "/nix/store/fixture-initrd";
            passthru = {
              retained = true;
              embeddedSignedFirmware = builtins.head system.boot.initrd.systemd.storePaths;
            };
          };
        in
        original // update original;
    };
  };
  originalInitrd = mkInitrd "/nix/store/fixture-original-signed" "gzip" [ ];
  overriddenInitrd = mkInitrd "/nix/store/fixture-overridden-signed" "gzip" [ ];
  formatSupported = compressor: prepend:
    (builtins.tryEval (mkInitrd "/nix/store/fixture-signed" compressor prepend)).success;
  executable = name: {
    type = "derivation";
    outPath = "/unused/${name}";
    meta.mainProgram = name;
  };
  mkFlasher = useFlashCmd: import ../../device-pkgs/initrdflash-script.nix {
    inherit lib useFlashCmd writeText;
    flashInitrd = overriddenInitrd;
    flashTools = "/unused/flash-tools";
    socType = "t234";
    buildPackages = {
      inherit coreutils findutils;
      runCommand = name: _: buildCommand: {
        outPath = "/unused/${name}";
        inherit buildCommand;
      };
    };
    nvidia-jetpack.firmwareMeasurements = executable "measure";
    writeShellApplication = attrs:
      let base = attrs // { buildCommand = ""; }; in
      base // { overrideAttrs = update: base // update base; };
    mkRcmBootScript = _: ''
      touch "$marker"
      exit 0
    '';
    mkRcmBootArgs = args: args;
    mkFlashCmdTools = _: "/unused/prepared-rcm";
    l4tMajorMinorPatchVersion = "36.5.2";
    deviceTree = { };
    tio = executable "tio";
    expect = executable "expect";
    config.hardware.nvidia-jetpack = {
      name = "fixture";
      flashScriptOverrides = {
        initrdFlashSerialEnumerateTimeoutSeconds = 1;
        initrdFlashCompletionTimeoutSeconds = 1;
      };
    };
  };
  flashers = map mkFlasher [ false true ];
  scripts = map
    (flasher: writeText "flash-payload-check.sh" (builtins.replaceStrings
      [ (builtins.placeholder "out") ] [ "$payloadRoot" ]
      flasher.text))
    flashers;
in
assert originalInitrd.passthru.retained;
assert overriddenInitrd.passthru.retained;
assert originalInitrd.passthru.signedFirmware == originalInitrd.passthru.embeddedSignedFirmware;
assert overriddenInitrd.passthru.signedFirmware == overriddenInitrd.passthru.embeddedSignedFirmware;
assert originalInitrd.passthru.signedFirmware != overriddenInitrd.passthru.signedFirmware;
assert builtins.all
  (flasher: lib.hasInfix
    "--signed-directory ${overriddenInitrd.passthru.signedFirmware}"
    flasher.passthru.payloadBundle.buildCommand)
  flashers;
assert lib.hasInfix
  "ln -s /unused/flash-tools \"$out/libexec/rcm\""
  (builtins.head flashers).passthru.payloadBundle.buildCommand;
assert formatSupported "gzip" [ ];
assert formatSupported "zstd" [ ];
assert formatSupported "cat" [ ];
assert !(formatSupported "xz" [ ]);
assert !(formatSupported (_: "/unused/gzip") [ ]);
assert !(formatSupported "gzip" [ "/unused/prepended.cpio" ]);
runCommand "jetson-flash-initrd-test"
{
  nativeBuildInputs = [ bash coreutils findutils ];
} ''
  export LOCALE_ARCHIVE=${glibcLocales}/lib/locale/locale-archive
  export payloadRoot="$PWD/payload" marker="$PWD/rcm-started"
  mkdir -p "$payloadRoot/share/jetpack" "$payloadRoot/libexec" "$PWD/shared-rcm/bootloader"
  cd "$payloadRoot"
  printf 'prepared\n' > ../shared-rcm/README
  printf 'prepared\n' > ../shared-rcm/bootloader/flashcmd.txt
  for mode in multi single; do
    if [[ "$mode" == multi ]]; then
      payload=libexec/initrd
      ln -s "$PWD/../shared-rcm" libexec/rcm
    else
      rm libexec/rcm
      mkdir -p libexec/rcm/bootloader
      cp -r ../shared-rcm/. libexec/rcm/
      payload=libexec/rcm/bootloader/boot.img
    fi
    printf 'original\n' > "$payload"
    sha256sum "$payload" > share/jetpack/flash-payload.sha256
    find -H libexec/rcm \( -type f -o -type l \) -print0 |
      sort -z | xargs -0 sha256sum > share/jetpack/rcm-payload.sha256
    if [[ "$mode" == multi ]]; then
      script=${lib.escapeShellArg (builtins.elemAt scripts 0)}
    else
      script=${lib.escapeShellArg (builtins.elemAt scripts 1)}
    fi
    LC_ALL=en_US.UTF-8 bash "$script" > stdout 2> stderr
    test -e "$marker"
    rm "$marker"

    printf 'changed\n' > "$payload"
    if bash "$script" > stdout 2> stderr; then
      echo "The flasher accepted a changed payload" >&2
      exit 1
    fi
    test ! -e "$marker"
    [[ "$(< stderr)" == *"Flash payload verification failed; refusing to run RCM."* ]]

    printf 'original\n' > "$payload"
    if payloadRoot="$PWD/missing" bash "$script" > stdout 2> stderr; then
      echo "The flasher accepted a missing payload directory" >&2
      exit 1
    fi
    test ! -e "$marker"
    [[ "$(< stderr)" == *"Flash payload verification failed; refusing to run RCM."* ]]

    printf 'original\n' > "$payload"
    printf 'changed\n' > libexec/rcm/bootloader/flashcmd.txt
    if bash "$script" > stdout 2> stderr; then
      echo "The flasher accepted a changed RCM command" >&2
      exit 1
    fi
    test ! -e "$marker"
    [[ "$(< stderr)" == *"Flash payload verification failed; refusing to run RCM."* ]]
    printf 'prepared\n' > libexec/rcm/bootloader/flashcmd.txt
    rm libexec/rcm/bootloader/flashcmd.txt
    if bash "$script" > stdout 2> stderr; then
      echo "The flasher accepted a missing RCM command" >&2
      exit 1
    fi
    test ! -e "$marker"
    [[ "$(< stderr)" == *"Flash payload verification failed; refusing to run RCM."* ]]
    printf 'prepared\n' > libexec/rcm/bootloader/flashcmd.txt
    touch libexec/rcm/bootloader/extra
    if bash "$script" > stdout 2> stderr; then
      echo "The flasher accepted an extra RCM file" >&2
      exit 1
    fi
    test ! -e "$marker"
    [[ "$(< stderr)" == *"Flash payload verification failed; refusing to run RCM."* ]]
    rm libexec/rcm/bootloader/extra
  done
  touch "$out"
''
