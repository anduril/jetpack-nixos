{ lib
, runCommand
, writeShellScript
, runtimeShell
, python3
, openssl
, coreutils
, gitRepos
, l4tMajorMinorPatchVersion
}:
let
  nvOpteeSrc = gitRepos."tegra/optee-src/nv-optee";
  toolSrc = "${nvOpteeSrc}/optee/samples/ftpm-helper/host/tool";
  genEkbSrc = "${nvOpteeSrc}/optee/samples/hwkey-agent/host/tool/gen_ekb/gen_ekb.py";

  # ecdsa is required by NVIDIA's tools; nixpkgs marks it insecure
  # (CVE-2024-23342, wontfix), so building needs NIXPKGS_ALLOW_INSECURE=1.
  pythonEnv = python3.withPackages (ps: [
    ps.cryptography
    ps.pyaes
    ps.numpy
    ps.asn1crypto
    ps.oscrypto
    ps.pycryptodome
    ps.pycryptodomex
    ps.ecdsa
  ]);

  runtimePath = lib.makeBinPath [
    pythonEnv
    openssl
    coreutils
  ];

  # Output directories the tools may produce.
  outputDirs = "odm_out oem_out ftpm_out ca_out ftpm_kdk";

  # NVIDIA's tools chdir to their own directory and write output alongside
  # themselves, so we symlink sources into a per-invocation tmpdir. The .sh
  # tools need an explicit interpreter since #!/bin/bash doesn't resolve on NixOS.
  mkWrapper =
    name: cmd:
    writeShellScript name ''
      set -euo pipefail
      _ORIG_DIR="$(pwd)"
      _WORKSPACE="$(mktemp -d)"
      _cleanup() { rm -rf "$_WORKSPACE"; }
      trap _cleanup EXIT

      export PATH="${runtimePath}:$PATH"

      # Refuse to clobber an earlier run's output (EKB/KDK material isn't reproducible).
      for _outdir in ${outputDirs}; do
        if [ -e "$_ORIG_DIR/$_outdir" ]; then
          echo "error: $_ORIG_DIR/$_outdir already exists; move or remove it first" >&2
          exit 1
        fi
      done

      for _f in ${toolSrc}/*; do
        ln -sf "$_f" "$_WORKSPACE/$(basename "$_f")"
      done
      ln -sf ${genEkbSrc} "$_WORKSPACE/gen_ekb.py"

      ${cmd}

      for _outdir in ${outputDirs}; do
        if [ -d "$_WORKSPACE/$_outdir" ]; then
          mv "$_WORKSPACE/$_outdir" "$_ORIG_DIR/$_outdir"
        fi
      done
    '';

  wrappers = {
    ftpm-odm-ekb-gen = mkWrapper "ftpm-odm-ekb-gen"
      ''${pythonEnv}/bin/python3 "$_WORKSPACE/odm_ekb_gen.py" "$@"'';
    ftpm-oem-ekb-gen = mkWrapper "ftpm-oem-ekb-gen"
      ''${pythonEnv}/bin/python3 "$_WORKSPACE/oem_ekb_gen.py" "$@"'';
    ftpm-kdk-gen = mkWrapper "ftpm-kdk-gen"
      ''${pythonEnv}/bin/python3 "$_WORKSPACE/kdk_gen.py" "$@"'';
    ftpm-gen-ek-csr = mkWrapper "ftpm-gen-ek-csr"
      ''${runtimeShell} "$_WORKSPACE/ftpm_manufacturer_gen_ek_csr.sh" "$@"'';
    ftpm-ca-simulator = mkWrapper "ftpm-ca-simulator"
      ''${runtimeShell} "$_WORKSPACE/ftpm_manufacturer_ca_simulator.sh" "$@"'';
    gen-ekb = mkWrapper "gen-ekb"
      ''${pythonEnv}/bin/python3 "$_WORKSPACE/gen_ekb.py" "$@"'';
  };
in
runCommand "ftpm-manufacturing-tools-${l4tMajorMinorPatchVersion}"
{
  meta = {
    description = "NVIDIA fTPM ODM/OEM manufacturing tools (KDK and EKB generation, EK CSR generation, CA simulator)";
    platforms = lib.platforms.linux;
  };
} ''
  mkdir -p $out/bin
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: script: ''
    install -m755 ${script} $out/bin/${name}
  '') wrappers)}
''
