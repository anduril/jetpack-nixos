{
  inputs = {
    # Kernel build fails with nixpkgs master, but not 22.05. (During dtc compilation)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05";
  };

  outputs = { self, nixpkgs, ... }@inputs: let
    inherit (nixpkgs) lib;

    installer_minimal_config = {
      imports = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        ./module.nix
      ];
      # Avoids a bunch of extra modules we don't have in the tegra_defconfig, like "ata_piix",
      disabledModules = [ "profiles/all-hardware.nix" ];

      boot.initrd.includeDefaultModules = false;
      hardware.nvidia-jetpack.enable = true;
    };
  in {
    nixosConfigurations = {
      installer_minimal = nixpkgs.legacyPackages.aarch64-linux.nixos installer_minimal_config;
      installer_minimal_cross = nixpkgs.legacyPackages.x86_64-linux.pkgsCross.aarch64-multiplatform.nixos installer_minimal_config;
    };

    nixosModules.default = import ./module.nix;

    overlays.default = import ./overlay.nix;

    packages = {
      x86_64-linux = {
        # Flashing scripts _only_ work on x86_64-linux
        inherit (nixpkgs.legacyPackages.x86_64-linux.callPackage ./default.nix {})
          flash-script
          flash-orin-agx-devkit
          flash-xavier-nx-devkit
          flash-xavier-nx-prod;

        iso_minimal = self.nixosConfigurations.installer_minimal_cross.config.system.build.isoImage;
      };

      aarch64-linux = {
        iso_minimal = self.nixosConfigurations.installer_minimal.config.system.build.isoImage;
      };
    };
  };
}
