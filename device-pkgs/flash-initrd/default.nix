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
  system = pkgs.nixos [
    (import ./system.nix {
      inherit
        extraModules
        flashFromDevice
        signedFirmware
        usbIdentity;
    })
    extraConfig
  ];
in
assert pkgs.lib.assertMsg
  (builtins.isString system.config.boot.initrd.compressor
    && builtins.elem system.config.boot.initrd.compressor [ "gzip" "zstd" "cat" ])
  "Jetson firmware measurements require a gzip, zstd or uncompressed recovery initrd.";
assert pkgs.lib.assertMsg (system.config.boot.initrd.prepend == [ ])
  "Jetson firmware measurements require a single recovery initrd CPIO archive.";
system.initialRamdisk.overrideAttrs ({ passthru ? { }, ... }: {
  passthru = passthru // usbIdentity // { inherit signedFirmware; };
})
