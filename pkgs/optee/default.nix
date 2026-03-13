{ lib, self }:
lib.packagesFromDirectoryRecursive {
  inherit (self) callPackage;
  directory = ./.;
}
