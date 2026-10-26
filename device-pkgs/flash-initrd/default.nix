{ pkgs
, extraModules
, flashFromDevice
, signedFirmware
, extraConfig ? { }
}:

let
  usbIdentity = {
    manufacturer = "NixOS";
    product = "serial";
    serialnumber = "0";
  };
in
(pkgs.nixos [
  (import ./system.nix {
    inherit
      extraModules
      flashFromDevice
      signedFirmware
      usbIdentity;
  })
  extraConfig
]).initialRamdisk.overrideAttrs ({ passthru ? { }, ... }: {
  passthru = passthru // usbIdentity;
})
