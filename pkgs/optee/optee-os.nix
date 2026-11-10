{ optee-config, lib, ftpmHelperTa ? null, msTpm20RefTa ? null }:
optee-config.overrideAttrs (finalAttrs: _: {
  pname = "optee-os";

  # fTPM — set ftpmHelperTa/msTpm20RefTa to the TA derivations to embed them as early TAs
  inherit ftpmHelperTa msTpm20RefTa;

  # Stripped ELFs are used here rather than signed .ta files. Early TAs
  # are embedded directly in the OP-TEE binary image and do not require
  # signing — they inherit the same trust level as OP-TEE OS itself.
  # Only REE (file-system-loaded) TAs need to be signed.
  # See: https://optee.readthedocs.io/en/latest/building/trusted_applications.html#signing-of-tas
  #
  # Using enableFTPM (rather than ftpmHelperTa != null) ensures that if
  # enableFTPM = true but the TA paths weren't provided, you get an
  # immediate eval error instead of a silent disable of fTPM.
  earlyTaPaths = lib.optionals finalAttrs.enableFTPM [
    "${finalAttrs.ftpmHelperTa}/a6a3a74a-77cb-433a-990c-1dfb8a3fbc4c.stripped.elf"
    "${finalAttrs.msTpm20RefTa}/bc50d971-d4c9-42c4-82cb-343fb7f37896.stripped.elf"
  ];

  # NOTE: EARLY_TA_PATHS needs to be added outside of `makeFlags` since it is a
  # space separated list of paths. See
  # https://nixos.org/manual/nixpkgs/stable/#build-phase for more details.
  preBuild = lib.optionalString (finalAttrs.earlyTaPaths != [ ]) ''
    makeFlagsArray+=(EARLY_TA_PATHS="${toString finalAttrs.earlyTaPaths}")
  '';
})
