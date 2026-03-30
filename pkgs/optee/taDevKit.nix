{ optee-os }:
optee-os.overrideAttrs (finalAttrs: {
  pname = "optee-ta-dev-kit";
  makeFlags = finalAttrs.makeFlags or [ ] ++ [ "ta_dev_kit" ];
})
