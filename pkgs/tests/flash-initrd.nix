{ lib, runCommand, coreutils, bash, writeText }:
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
    socType = "t234";
    buildPackages = { inherit coreutils; };
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
    flasher.buildCommand)
  flashers;
assert formatSupported "gzip" [ ];
assert formatSupported "zstd" [ ];
assert formatSupported "cat" [ ];
assert !(formatSupported "xz" [ ]);
assert !(formatSupported (_: "/unused/gzip") [ ]);
assert !(formatSupported "gzip" [ "/unused/prepended.cpio" ]);
runCommand "jetson-flash-initrd-test"
{
  nativeBuildInputs = [ bash coreutils ];
} ''
  export payloadRoot="$PWD/payload" marker="$PWD/rcm-started"
  mkdir -p "$payloadRoot/share/jetpack" "$payloadRoot/libexec"
  cd "$payloadRoot"
  for script in ${lib.escapeShellArgs scripts}; do
    printf 'original\n' > libexec/initrd
    sha256sum libexec/initrd > share/jetpack/flash-payload.sha256
    bash "$script" > stdout 2> stderr
    test -e "$marker"
    rm "$marker"

    printf 'changed\n' > libexec/initrd
    if bash "$script" > stdout 2> stderr; then
      echo "The flasher accepted a changed payload" >&2
      exit 1
    fi
    test ! -e "$marker"
    [[ "$(< stderr)" == *"Flash payload verification failed; refusing to run RCM."* ]]

    printf 'original\n' > libexec/initrd
    if payloadRoot="$PWD/missing" bash "$script" > stdout 2> stderr; then
      echo "The flasher accepted a missing payload directory" >&2
      exit 1
    fi
    test ! -e "$marker"
    [[ "$(< stderr)" == *"Flash payload verification failed; refusing to run RCM."* ]]
  done
  touch "$out"
''
