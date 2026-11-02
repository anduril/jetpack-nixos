{ otaUtils
, runCommand
, writeShellScriptBin
,
}:

let
  fakeTegraEepromTool = writeShellScriptBin "tegra-boardspec" ''
    printf '%s\n' '3701-300-0000-A.0-fuselevel_production-0'
  '';

  otaUtilsForTest = otaUtils.override {
    tegra-eeprom-tool = fakeTegraEepromTool;
  };
in
runCommand "ota-utils-test" { } ''
  output=$(PATH=/no-such-path ${otaUtilsForTest}/bin/ota-check-firmware -h 2>&1)

  case "$output" in
    *"command not found"*)
      printf '%s\n' "$output" >&2
      exit 1
      ;;
  esac

  [[ "$output" == *"Check Jetson firmware status"* ]]
  touch "$out"
''
