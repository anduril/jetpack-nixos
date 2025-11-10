{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    cuda-legacy = {
      url = "github:nixos-cuda/cuda-legacy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
      jetpack5_config = {
        hardware.nvidia-jetpack.majorVersion = "5";
      };
      jetpack7_config = {
        hardware.nvidia-jetpack.majorVersion = "7";
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
        installer_minimal_jp5 = nixpkgs.lib.nixosSystem {
          modules = [ aarch64_config installer_minimal_config jetpack5_config ];
        };
        installer_minimal_cross_jp5 = nixpkgs.lib.nixosSystem {
          modules = [ aarch64_cross_config installer_minimal_config jetpack5_config ];
        };
        installer_minimal_jp7 = nixpkgs.lib.nixosSystem {
          modules = [ aarch64_config installer_minimal_config jetpack7_config ];
        };
        installer_minimal_cross_jp7 = nixpkgs.lib.nixosSystem {
          modules = [ aarch64_cross_config installer_minimal_config jetpack7_config ];
        };
      };

      nixosModules.default = import ./modules/default.nix;

      overlays.default = import ./overlay.nix;

      packages = {
        x86_64-linux =
          let
            supportedConfigurations = lib.listToAttrs (map
              (c: {
                name = c.som + lib.optionalString (c.super or false) "-super" + "-${c.carrierBoard}" + lib.optionalString (c ? majorVersion) "-jp${c.majorVersion}";
                value = c;
              }) [
              { som = "orin-agx"; carrierBoard = "devkit"; }
              { som = "orin-agx-industrial"; carrierBoard = "devkit"; }
              { som = "orin-nx"; carrierBoard = "devkit"; }
              { som = "orin-nano"; carrierBoard = "devkit"; }
              { som = "orin-nx"; carrierBoard = "devkit"; super = true; }
              { som = "orin-nano"; carrierBoard = "devkit"; super = true; }
              { som = "orin-agx"; carrierBoard = "devkit"; majorVersion = "5"; }
              { som = "orin-agx-industrial"; carrierBoard = "devkit"; majorVersion = "5"; }
              { som = "orin-nx"; carrierBoard = "devkit"; majorVersion = "5"; }
              { som = "orin-nano"; carrierBoard = "devkit"; majorVersion = "5"; }
              { som = "orin-nx"; carrierBoard = "devkit"; super = true; majorVersion = "5"; }
              { som = "orin-nano"; carrierBoard = "devkit"; super = true; majorVersion = "5"; }
              { som = "thor-agx"; carrierBoard = "devkit"; }
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
            iso_minimal = self.nixosConfigurations.installer_minimal_cross.config.system.build.isoImage;
            iso_minimal_jp5 = self.nixosConfigurations.installer_minimal_cross_jp5.config.system.build.isoImage;
            iso_minimal_jp7 = self.nixosConfigurations.installer_minimal_cross_jp7.config.system.build.isoImage;

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
          iso_minimal_jp5 = self.nixosConfigurations.installer_minimal_jp5.config.system.build.isoImage;
          iso_minimal_jp7 = self.nixosConfigurations.installer_minimal_jp7.config.system.build.isoImage;
        };
      };

      checks = forAllSystems ({ pkgs, system, ... }: {
        formatting = pkgs.stdenv.mkDerivation {
          name = "repo-formatting";
          src = self;
          buildPhase = ''
            ${lib.getExe self.formatter.${system}} --fail-on-change --no-cache && touch $out
          '';
        };
        jetpackSelectionDependsOnCudaVersion = import ./check-jetpack-selection.nix {
          inherit lib nixpkgs pkgs system;
          overlay = self.overlays.default;
        };
      });

      formatter = forAllSystems ({ pkgs, ... }: import ./treefmt.nix pkgs);

      legacyPackages = forAllSystems ({ system, ... }:
        let
          pkgs =
            (import nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
                cudaCapabilities = [ "7.2" "8.7" ];
                cudaSupport = true;
              };
              overlays = [ self.overlays.default ];
            });
        in
        pkgs.nvidia-jetpack // { inherit (pkgs) nvidia-jetpack5 nvidia-jetpack6 nvidia-jetpack7; }
      );
    };
}
