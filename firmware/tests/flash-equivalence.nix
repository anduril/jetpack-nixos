# Stock flash.sh's output (reference.*) against the decomposed output, for this
# configuration as it is: signedFirmware per flash.idx partition outside the
# stock-random fields; bup per payload entry; all in one derivation. The
# capsule is the same derivation over either bup, so it isn't compared.
# T264 PKC+SBK is not compared: its compressed dce/rce need a decrypt-compare.
{ lib, config, pkgs, devicePkgs, extensions, jetpack, toolsPkgs }:
let
  cfg = config.hardware.nvidia-jetpack;
  inherit (cfg.firmware.secureBoot) pkcFile sbkFile;
  # SBK output is random per run on both sides: compare another instance of
  # the same configuration with the IVs fixed.
  jetpack' =
    if sbkFile == null then jetpack
    else
      jetpack.overrideScope (import ../../firmware-packages.nix {
        inherit pkgs devicePkgs extensions;
        config = config // {
          hardware = config.hardware // {
            nvidia-jetpack = cfg // {
              flashScriptOverrides = cfg.flashScriptOverrides // {
                flashArgs = [ "--disable-random-iv" ] ++ cfg.flashScriptOverrides.flashArgs;
              };
            };
          };
        };
      }).extension;
  flashTools = jetpack'.l4tFlashTools;
  # PKC: the nested sb-pkg and hpse-pkg headers' signature fields aren't modelled yet.
  mayDiffer = lib.optionals (pkcFile != null) [ "sb-pkg" "hpse-pkg" ];

  # One derivation, so a change to any of the three rebuilds the comparison
  # of both. In a flash-tools tree like the signing derivations', so
  # preSignCommands (the PKCS#11 token) run as they do there, and whose python
  # has cryptography and python-pkcs11.
  compare = ref: cand: extra: ''
    python3 -I ${./flash-equivalence.py} ${ref} ${cand} --may-differ=${lib.concatStringsSep "," mayDiffer} \
      ${lib.optionalString (pkcFile != null) "--pkc ${lib.escapeShellArg pkcFile}"} --soc ${jetpack'.socType} ${extra} | tee -a $out
  '';
in
toolsPkgs.runCommand "flash-equivalence-${cfg.name}" cfg.firmware.secureBoot.derivationAttrs
  (jetpack'.mkFlashScript flashTools {
    flashCommands = ''
      ${cfg.firmware.secureBoot.preSignCommands toolsPkgs}
      ${compare jetpack'.reference.signedFirmware jetpack'.decomposed.signedFirmware ""}
      ${compare jetpack'.reference.bup jetpack'.decomposed.bup "--bup ${flashTools}/bootloader/BUP_generator.py"}
    '';
  })
