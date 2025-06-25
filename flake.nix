{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/backport-401840-to-release-25.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      allSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs allSystems (system: f {
        pkgs = nixpkgs.legacyPackages.${system};
        inherit system;
      });

      installer_minimal_config = {
        imports = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          self.nixosModules.default
        ];
        # Avoids a bunch of extra modules we don't have in the tegra_defconfig, like "ata_piix",
        hardware.enableAllHardware = lib.mkForce false;

        hardware.nvidia-jetpack.enable = true;
      };
      aarch64_config = {
        nixpkgs = {
          buildPlatform = "aarch64-linux";
          hostPlatform = "aarch64-linux";
        };
      };
      aarch64_cross_config = {
        nixpkgs = {
          buildPlatform = "x86_64-linux";
          hostPlatform = "aarch64-linux";
        };

      };
    in
    {
      nixosConfigurations = {
        installer_minimal = nixpkgs.lib.nixosSystem {
          modules = [ aarch64_config installer_minimal_config ];
        };
        installer_minimal_cross = nixpkgs.lib.nixosSystem {
          modules = [ aarch64_cross_config installer_minimal_config ];
        };
      };

      nixosModules.default = import ./modules/default.nix;

      overlays.default = import ./overlay.nix;

      packages = {
        x86_64-linux =
          let
            supportedConfigurations = lib.listToAttrs (map
              (c: {
                name = "${c.som}" + (lib.optionalString (c.super or false) "-super") + "-${c.carrierBoard}";
                value = c;
              }) [
              { som = "orin-agx"; carrierBoard = "devkit"; }
              { som = "orin-agx-industrial"; carrierBoard = "devkit"; }
              { som = "orin-nx"; carrierBoard = "devkit"; }
              { som = "orin-nano"; carrierBoard = "devkit"; }
              { som = "orin-nx"; carrierBoard = "devkit"; super = true; }
              { som = "orin-nano"; carrierBoard = "devkit"; super = true; }
              { som = "xavier-agx"; carrierBoard = "devkit"; }
              { som = "xavier-agx-industrial"; carrierBoard = "devkit"; } # TODO: Entirely untested
              { som = "xavier-nx"; carrierBoard = "devkit"; }
              { som = "xavier-nx-emmc"; carrierBoard = "devkit"; }
            ]);

            supportedNixOSConfigurations = lib.mapAttrs
              (n: c: (nixpkgs.lib.nixosSystem {
                modules = [
                  aarch64_cross_config
                  self.nixosModules.default
                  {
                    hardware.nvidia-jetpack = { enable = true; } // c;
                    networking.hostName = "${c.som}-${c.carrierBoard}"; # Just so it sets the flash binary name.
                  }
                ];
              }).config)
              supportedConfigurations;

            flashScripts = lib.mapAttrs' (n: c: lib.nameValuePair "flash-${n}" c.system.build.flashScript) supportedNixOSConfigurations;
            initrdFlashScripts = lib.mapAttrs' (n: c: lib.nameValuePair "initrd-flash-${n}" c.system.build.initrdFlashScript) supportedNixOSConfigurations;
            uefiCapsuleUpdates = lib.mapAttrs' (n: c: lib.nameValuePair "uefi-capsule-update-${n}" c.system.build.uefiCapsuleUpdate) supportedNixOSConfigurations;
          in
          {
            # TODO: Untested
            iso_minimal = self.nixosConfigurations.installer_minimal_cross.config.system.build.isoImage;

            inherit (self.legacyPackages.x86_64-linux)
              board-automation python-jetson;
            inherit (self.legacyPackages.x86_64-linux.cudaPackages)
              nsight_systems_host nsight_compute_host;
          }
          # Flashing and board automation scripts _only_ work on x86_64-linux
          // flashScripts
          // initrdFlashScripts
          // uefiCapsuleUpdates;

        aarch64-linux = {
          iso_minimal = self.nixosConfigurations.installer_minimal.config.system.build.isoImage;
        };
      };

      checks = forAllSystems ({ pkgs, ... }: {
        formatting = pkgs.runCommand "repo-formatting" { nativeBuildInputs = with pkgs; [ nixpkgs-fmt ]; } ''
          nixpkgs-fmt --check ${self} && touch $out
        '';
      });

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixpkgs-fmt);

      legacyPackages = forAllSystems ({ system, ... }:
        (import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaCapabilities = [ "7.2" "8.7" ];
            cudaSupport = true;
          };
          overlays = [
            self.overlays.default
            (final: prev: {
              # NOTE: samples (and other packages) may pull in dependencies which depend on CUDA (either directly or
              # transitively) -- this is problematic for us, because the default CUDA package set is not the one we
              # construct.
              # To avoid mixed package sets, we make our CUDA package set the default.
              inherit (final.nvidia-jetpack) cudaPackages;
              # TODO: Remove after bumping past 24.11: reset OpenCV's override on cudaPackages.
              # https://github.com/NixOS/nixpkgs/blob/7ffe0edc685f14b8c635e3d6591b0bbb97365e6c/pkgs/top-level/all-packages.nix#L10540-L10541
              opencv4 = prev.opencv4.override { inherit (final) cudaPackages; };
            })
          ];
        }).nvidia-jetpack
      );
    };
}
