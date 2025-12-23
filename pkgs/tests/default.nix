{ callPackage
}:
{
  oci = callPackage ./oci { };

  dlopen-override = callPackage ./dlopen-override.nix { };
}
