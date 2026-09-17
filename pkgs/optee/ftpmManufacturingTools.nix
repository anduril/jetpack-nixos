{ lib
, stdenvNoCC
, makeWrapper
, python3
, openssl
, coreutils
, gitRepos
, l4tMajorMinorPatchVersion
, l4tAtLeast
, l4tOlder
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

  installOverride = name: path: lib.optionalString (path != null) ''
    install -m 755 ${lib.escapeShellArg "${path}"} $out/libexec/ftpm/${name}
  '';

  # JP7 (l4t 39+) dropped the ftpm_manufacturer_*.sh script hooks in favor
  # of the CA-class hook; see ./ftpmManufacturingTools-overrides.md.
  warnIfWrongVersion = name: applicable: path:
    if path != null && !applicable then
      lib.warn "${name} has no effect on l4t ${l4tMajorMinorPatchVersion}; ignoring" null
    else
      path;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ftpm-manufacturing-tools";
  version = l4tMajorMinorPatchVersion;

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  # Override hooks (via overrideAttrs) to replace NVIDIA's EK CSR generator,
  # CA simulator, and/or (JP7 only) CA signing class with site-specific
  # implementations. See ./ftpmManufacturingTools-overrides.md.
  vendored_ftpm_manufacturer_gen_ek_csr = null;
  vendored_ftpm_manufacturer_ca_simulator = null;
  vendored_ftpm_ca_class = null;

  # NVIDIA's tools assume they're run from their own source directory:
  # odm_ekb_gen.py/oem_ekb_gen.py chdir to their own location before doing
  # relative-path I/O, and the shell tools reference sibling scripts/config
  # by relative path. Since we copy everything into $out/libexec (a
  # read-only store path), drop the chdir calls and make those references
  # absolute, so the tools instead read/write relative to the caller's cwd.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/ftpm $out/bin
    cp -r ${toolSrc}/. $out/libexec/ftpm/
    cp ${genEkbSrc} $out/libexec/ftpm/gen_ekb.py
    chmod -R u+w $out/libexec/ftpm

    substituteInPlace $out/libexec/ftpm/odm_ekb_gen.py \
      --replace-fail \
        'os.path.dirname(os.path.abspath(__file__))' \
        'os.getcwd()' \
      --replace-fail \
        'os.chdir(wd)' \
        'pass'
    ${lib.optionalString (l4tOlder "39") ''
      substituteInPlace $out/libexec/ftpm/odm_ekb_gen.py \
        --replace-fail \
          'cmd_gen_ek_csr = "./ftpm_manufacturer_gen_ek_csr.sh"' \
          'cmd_gen_ek_csr = "'"$out"'/libexec/ftpm/ftpm_manufacturer_gen_ek_csr.sh"' \
        --replace-fail \
          'cmd_gen_ek_certs = "./ftpm_manufacturer_ca_simulator.sh"' \
          'cmd_gen_ek_certs = "'"$out"'/libexec/ftpm/ftpm_manufacturer_ca_simulator.sh"'
    ''}
    ${lib.optionalString (l4tAtLeast "36" && l4tOlder "39") ''
      substituteInPlace $out/libexec/ftpm/odm_ekb_gen.py \
        --replace-fail \
          'cmd_sign_sid_csr = "./ftpm_manufacturer_ca_sign_sid_csr.sh"' \
          'cmd_sign_sid_csr = "'"$out"'/libexec/ftpm/ftpm_manufacturer_ca_sign_sid_csr.sh"'
    ''}
    substituteInPlace $out/libexec/ftpm/oem_ekb_gen.py \
      --replace-fail \
        'os.path.dirname(os.path.abspath(__file__))' \
        'os.getcwd()' \
      --replace-fail \
        'os.chdir(wd)' \
        'pass' \
      --replace-fail \
        'cmd_gen_ekb = "./gen_ekb.py"' \
        'cmd_gen_ekb = "'"$out"'/libexec/ftpm/gen_ekb.py"'

    if [ -f "$out/libexec/ftpm/ftpm_manufacturer_gen_ek_csr.sh" ]; then
      substituteInPlace $out/libexec/ftpm/ftpm_manufacturer_gen_ek_csr.sh \
        --replace-fail \
          'FTPM_GEN_EK_CSR_PYTHON_SCRIPT="./ftpm_manufacturer_gen_ek_csr_tool.py"' \
          'FTPM_GEN_EK_CSR_PYTHON_SCRIPT="'"$out"'/libexec/ftpm/ftpm_manufacturer_gen_ek_csr_tool.py"'
    fi
    if [ -f "$out/libexec/ftpm/ftpm_manufacturer_ca_simulator.sh" ]; then
      substituteInPlace $out/libexec/ftpm/ftpm_manufacturer_ca_simulator.sh \
        --replace-fail \
          'CONF_PATH="./conf"' \
          'CONF_PATH="'"$out"'/libexec/ftpm/conf"' \
        --replace-fail \
          'CA_SIM_PYTHON_SCRIPT="./ftpm_manufacturer_ca_simulator.py"' \
          'CA_SIM_PYTHON_SCRIPT="'"$out"'/libexec/ftpm/ftpm_manufacturer_ca_simulator.py"'
    fi
    if [ -f "$out/libexec/ftpm/ftpm_manufacturer_ca_sign_sid_csr.sh" ]; then
      substituteInPlace $out/libexec/ftpm/ftpm_manufacturer_ca_sign_sid_csr.sh \
        --replace-fail \
          'CONF_PATH="./conf"' \
          'CONF_PATH="'"$out"'/libexec/ftpm/conf"' \
        --replace-fail \
          'CA_SIM_PYTHON_SCRIPT="./ftpm_manufacturer_ca_sign_sid_csr.py"' \
          'CA_SIM_PYTHON_SCRIPT="'"$out"'/libexec/ftpm/ftpm_manufacturer_ca_sign_sid_csr.py"'
    fi

    ${installOverride "ftpm_manufacturer_gen_ek_csr.sh" (warnIfWrongVersion "vendored_ftpm_manufacturer_gen_ek_csr" (l4tOlder "39") finalAttrs.vendored_ftpm_manufacturer_gen_ek_csr)}
    ${installOverride "ftpm_manufacturer_ca_simulator.sh" (warnIfWrongVersion "vendored_ftpm_manufacturer_ca_simulator" (l4tOlder "39") finalAttrs.vendored_ftpm_manufacturer_ca_simulator)}

    ${lib.optionalString ((warnIfWrongVersion "vendored_ftpm_ca_class" (l4tAtLeast "39") finalAttrs.vendored_ftpm_ca_class) != null) ''
      install -m 644 ${lib.escapeShellArg "${finalAttrs.vendored_ftpm_ca_class}"} $out/libexec/ftpm/lib/custom_ca.py
      substituteInPlace $out/libexec/ftpm/odm_ekb_gen.py \
        --replace-fail \
          'from lib.ca_signing import SimulatorCA, ca_sign_ek_csrs, ca_sign_sid_csr' \
          'from lib.ca_signing import ca_sign_ek_csrs, ca_sign_sid_csr
    from lib.custom_ca import CustomCA as SimulatorCA'
    ''}

    patchShebangs $out/libexec/ftpm

    makeWrapper ${pythonEnv}/bin/python3 $out/bin/ftpm-odm-ekb-gen \
      --add-flags $out/libexec/ftpm/odm_ekb_gen.py \
      --prefix PATH : ${runtimePath}
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/ftpm-oem-ekb-gen \
      --add-flags $out/libexec/ftpm/oem_ekb_gen.py \
      --prefix PATH : ${runtimePath}
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/ftpm-kdk-gen \
      --add-flags $out/libexec/ftpm/kdk_gen.py \
      --prefix PATH : ${runtimePath}
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/gen-ekb \
      --add-flags $out/libexec/ftpm/gen_ekb.py \
      --prefix PATH : ${runtimePath}
    if [ -f "$out/libexec/ftpm/ftpm_manufacturer_gen_ek_csr.sh" ]; then
      makeWrapper $out/libexec/ftpm/ftpm_manufacturer_gen_ek_csr.sh $out/bin/ftpm-gen-ek-csr \
        --prefix PATH : ${runtimePath}
    fi
    if [ -f "$out/libexec/ftpm/ftpm_manufacturer_ca_simulator.sh" ]; then
      makeWrapper $out/libexec/ftpm/ftpm_manufacturer_ca_simulator.sh $out/bin/ftpm-ca-simulator \
        --prefix PATH : ${runtimePath}
    fi

    runHook postInstall
  '';

  meta = {
    description = "NVIDIA fTPM ODM/OEM manufacturing tools (KDK and EKB generation, EK CSR generation, CA simulator)";
    platforms = lib.platforms.linux;
  };
})
