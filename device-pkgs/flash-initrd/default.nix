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
  # Do not use pkgs.nixos: downstream overrides may import Nixpkgs again.
  # readOnlyPkgs also rejects config/overlays in extraConfig instead of quietly
  # ignoring them. system = null leaves both platforms to the supplied pkgs.
  flashFirmwareSystem = import (pkgs.path + /nixos/lib/eval-config.nix) {
    system = null;
    modules = [
      (pkgs.path + /nixos/modules/misc/nixpkgs/read-only.nix)
      { nixpkgs.pkgs = pkgs; }
      (import ./system.nix {
        inherit extraModules flashFromDevice signedFirmware usbIdentity;
      })
      extraConfig
    ];
  };
in
assert pkgs.lib.assertMsg pkgs.stdenv.hostPlatform.isAarch64 "The flashing initrd runtime package set must target aarch64";
flashFirmwareSystem.config.system.build.initialRamdisk.overrideAttrs ({ passthru ? { }, ... }: {
  passthru = passthru // usbIdentity // {
    # "system" is already the derivation's BUILD platform, not this config.
    flashInitrdConfig = flashFirmwareSystem.config;
  };
})
