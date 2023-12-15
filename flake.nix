{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      installer_minimal_config = {
        imports = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./modules/default.nix
        ];
        # Avoids a bunch of extra modules we don't have in the tegra_defconfig, like "ata_piix",
        disabledModules = [ "profiles/all-hardware.nix" ];

        hardware.nvidia-jetpack.enable = true;
      };

      x86_packages = nixpkgs.legacyPackages.x86_64-linux.callPackage ./default.nix { };
    in
    {
      nixosConfigurations = {
        installer_minimal = nixpkgs.legacyPackages.aarch64-linux.nixos installer_minimal_config;
        installer_minimal_cross = nixpkgs.legacyPackages.x86_64-linux.pkgsCross.aarch64-multiplatform.nixos installer_minimal_config;
      };

      nixosModules.default = import ./modules/default.nix;

      overlays.default = import ./overlay.nix;

      packages = {
        x86_64-linux = {
          # TODO: Untested
          iso_minimal = self.nixosConfigurations.installer_minimal_cross.config.system.build.isoImage;

          inherit (x86_packages)
            board-automation python-jetson;
          inherit (x86_packages.cudaPackages)
            nsight_systems_host nsight_compute_host;
        }
        # Flashing and board automation scripts _only_ work on x86_64-linux
        // x86_packages.flashScripts
        // x86_packages.initrdFlashScripts
        // x86_packages.uefiCapsuleUpdates;

        aarch64-linux = {
          iso_minimal = self.nixosConfigurations.installer_minimal.config.system.build.isoImage;
        };
      };

      checks = nixpkgs.lib.mapAttrs
        (system: _: {
          formatting = nixpkgs.legacyPackages.${system}.callPackage ./ci/formatting.nix { };
        })
        self.legacyPackages;

      # Not everything here should be cross-compiled to aarch64-linux
      legacyPackages.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.callPackage ./default.nix { };
      legacyPackages.aarch64-linux = nixpkgs.legacyPackages.aarch64-linux.callPackage ./default.nix { };
    };
}
