# Derivations that sign the leaf images jetpack-nixos supplies (UEFI, TOS, kernel
# DTB, ...), in place of the stub inputs NVIDIA's `flash.sh --sign` signs.
# `reference` throughout: a variant's baseColdboot, the stock flash.sh
# run whose layout and ratchet blob the leaves are signed against. The
# per-variant leaves are in variant.nix.
{ lib, pkgs, runCommand, cfg, jetpack, defaultColdboot }:
let
  inherit (jetpack) l4tMajorMinorPatchVersion tosImage socType chipId;

  signArgs = reference: name: {
    inherit pkgs;
    flash-tools = jetpack.l4tFlashTools;
    name = "${cfg.name}-${name}-${l4tMajorMinorPatchVersion}";
    ratchetBlob = "${reference}/ratchet_blob.bin";
    inherit chipId;
    inherit (cfg.flashScriptOverrides) flashArgs;
    inherit (cfg.firmware.secureBoot) pkcFile sbkFile preSignCommands requiredSystemFeatures noChroot;
  };
  sign = reference: name: partition: args: jetpack.signImage (signArgs reference name) ({
    inherit partition;
    layout = "${reference}/flash.xml.tmp";
  } // args);
  # tegraflash_create_secure_fip (r39.2.1 tegraflash_impl_t264.py:1652-1684),
  # in its order; mods_t264.pkg is not in the BSP.
  stmm = "standalonemm_jetson.pkg";
  spFip = runCommand "${cfg.name}-sp-fip-${l4tMajorMinorPatchVersion}" { } ''
    install -m 644 ${tosImage}/tos.img tos-optee_t264.img
    cp ${defaultColdboot}/inputs/${stmm} .
    ${jetpack.l4tFlashTools}/bootloader/fiptool create --align 0x1000 \
      --blob uuid=486178e0-e7f8-11e3-bc5e-0002a5d5c51b,file=tos-optee_t264.img --blob uuid=9b12fb8a-6047-ca64-88c8-18864a6caa4c,file=${stmm} sp_t264.fip
    mkdir $out
    cp sp_t264.fip $out/
  '';

  # Board-independent leaves (OP-TEE, ATF, EKS), signed once with variant0's layout and ratchet.
  common = lib.optionalAttrs (socType == "t234")
    {
      secure-os = sign defaultColdboot "tos" "A_secure-os" { fileName = "tos-optee_t234.img"; image = "${tosImage}/tos.img"; };
    } // lib.optionalAttrs (socType == "t264") {
    sec-partition = sign defaultColdboot "sec-partition" "A_sec-partition" { fileName = "sp_t264.fip"; image = "${spFip}/sp_t264.fip"; };
    atf = sign defaultColdboot "atf" "A_atf" { fileName = "bl31_t264.fip"; image = "${tosImage}/bl31.fip"; };
  } // lib.optionalAttrs (cfg.firmware.eksFile != null) {
    eks = sign defaultColdboot "eks" "A_eks" { fileName = "eks_${socType}.img"; image = cfg.firmware.eksFile; };
  };
in
{
  inherit sign common;

}
