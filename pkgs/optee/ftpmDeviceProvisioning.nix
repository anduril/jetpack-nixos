{ lib
, runCommand
, writeShellScript
, runtimeShell
, gitRepos
, l4tMajorMinorPatchVersion
}:
let
  toolSrc = "${gitRepos."tegra/optee-src/nv-optee"}/optee/samples/ftpm-helper/host/tool";

  # #!/bin/bash shebang does not resolve on NixOS, so run through runtimeShell.
  mkWrapper =
    name: script:
    writeShellScript name ''
      exec ${runtimeShell} ${toolSrc}/${script} "$@"
    '';

  wrappers = {
    ftpm-device-provision = mkWrapper "ftpm-device-provision" "ftpm_device_provision.sh";
    ftpm-offline-verify = mkWrapper "ftpm-offline-verify" "ftpm_offline_provisioning_verify.sh";
    ftpm-test-attestation = mkWrapper "ftpm-test-attestation" "ftpm_test_local_attestation.sh";
  };
in
runCommand "ftpm-device-provisioning-${l4tMajorMinorPatchVersion}"
{
  meta = {
    description = "NVIDIA fTPM on-device provisioning and verification scripts";
    platforms = [ "aarch64-linux" ];
  };
}
  ''
    mkdir -p $out/bin
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: script: ''
        install -m755 ${script} $out/bin/${name}
      '') wrappers
    )}
  ''
