{ optee-os }:
optee-os.overrideAttrs (finalAttrs: {
  pname = "optee-ta-dev-kit";
  uefi-firmware = null;
  ftpmHelperTa = null;
  msTpm20RefTa = null;
  makeFlags = finalAttrs.makeFlags or [ ] ++ [ "ta_dev_kit" ];
})
