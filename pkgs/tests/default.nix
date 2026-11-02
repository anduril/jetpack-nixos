{ callPackage
}:
{
  oci = callPackage ./oci { };

  dlopen-override = callPackage ./dlopen-override.nix { };
  ota-utils = callPackage ./ota-utils.nix { };
}
