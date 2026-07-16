{ optee-os }:
# Break the optee-os → fTPM TA → taDevKit → optee-os evaluation cycle by
# nulling out the fTPM TA refs taDevKit doesn't need, and clamping
# earlyTaPaths to [] explicitly. Without the earlyTaPaths override,
# optee-os.nix would compute it from finalAttrs.enableFTPM (inherited
# from the overlay) and try to interpolate the null TA refs.
optee-os.overrideAttrs (finalAttrs: {
  pname = "optee-ta-dev-kit";
  uefi-firmware = null;
  ftpmHelperTa = null;
  msTpm20RefTa = null;
  earlyTaPaths = [ ];
  makeFlags = finalAttrs.makeFlags or [ ] ++ [ "ta_dev_kit" ];
})
