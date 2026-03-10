{ coreutils, gitRepos, l4tMajorMinorPatchVersion, stdenv, writeShellScriptBin }:

let
  ftpmSimToolWrapper = writeShellScriptBin "ftpm_sim_provisioning_tool.sh" ''
    set -euo pipefail
    script_dir="''${0%/*}/../share/ftpm-sim-tooling"
    work_dir="/run/ghaf-ftpm-sim-tooling"

    ${coreutils}/bin/rm -rf "$work_dir"
    ${coreutils}/bin/mkdir -p "$work_dir"
    ${coreutils}/bin/cp -R "$script_dir/conf" "$work_dir/conf"
    ${coreutils}/bin/cp "$script_dir/ftpm_sim_provisioning_tool.sh" "$work_dir/"

    cd "$work_dir"
    exec ./ftpm_sim_provisioning_tool.sh "$@"
  '';
in

stdenv.mkDerivation {
  pname = "ftpm-sim-tooling";
  version = l4tMajorMinorPatchVersion;
  src = gitRepos."tegra/optee-src/nv-optee";
  dontBuild = true;
  installPhase = ''
    runHook preInstall

    tool_dir="optee/samples/ftpm-helper/host/tool"

    install -Dm755 "$tool_dir/ftpm_sim_provisioning_tool.sh" \
      "$out/share/ftpm-sim-tooling/ftpm_sim_provisioning_tool.sh"

    install -Dm644 "$tool_dir/conf/ftpm_sim_root_ca_csr.config" \
      "$out/share/ftpm-sim-tooling/conf/ftpm_sim_root_ca_csr.config"
    install -Dm644 "$tool_dir/conf/ftpm_sim_i_ca_csr.config" \
      "$out/share/ftpm-sim-tooling/conf/ftpm_sim_i_ca_csr.config"
    install -Dm644 "$tool_dir/conf/ftpm_sim_ek_csr.config" \
      "$out/share/ftpm-sim-tooling/conf/ftpm_sim_ek_csr.config"

    substituteInPlace "$out/share/ftpm-sim-tooling/ftpm_sim_provisioning_tool.sh" \
      --replace-fail '#!/bin/bash' '#!${stdenv.shell}'

    install -Dm755 "${ftpmSimToolWrapper}/bin/ftpm_sim_provisioning_tool.sh" \
      "$out/bin/ftpm_sim_provisioning_tool.sh"

    runHook postInstall
  '';
}
