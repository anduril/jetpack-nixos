let
  self = builtins.getFlake (builtins.toString ../.);
  inherit (self.inputs.nixpkgs) lib;

  getFlasherScripts = deviceName:
    lib.concatMapAttrs
      (name: value:
        let
          cross = value.extendModules {
            modules = [
              {
                nixpkgs = {
                  buildPlatform.system = "x86_64-linux";
                  hostPlatform.system = "aarch64-linux";
                };
                # Cross-compilation isn't currently supported for cuda packages upstream, and causes an huge evaluation slowdown.
                hardware.nvidia-jetpack.configureCuda = false;
              }
            ];
          };
        in
        lib.optionalAttrs (lib.hasPrefix deviceName name)
          { "${name}-flashScript".x86_64-linux = cross.config.system.build.flashScript; })
      self.nixosConfigurations;

  mkJetPackPackageSet =
    cudaPackagesName:
    cudaCapability:
    let
      common = import ./common.nix {
        evalSystem = "aarch64-linux";
        supportedSystems = [ "aarch64-linux" ];
        cudaSupport = true;
        cudaCapabilities = [ cudaCapability ];
        extraOverlays = [
          (final: prev: {
            cudaPackages = builtins.getAttr cudaPackagesName final;
          })
        ];
      };
      inherit (common.releaseLib) mapTestOn packagePlatforms pkgs;
    in
    (mapTestOn (packagePlatforms { inherit (pkgs) nvidia-jetpack; })).nvidia-jetpack;
in
{
  xavier = {
    nvidia-jetpack5 = mkJetPackPackageSet "cudaPackages_11_4" "7.2";
  } // getFlasherScripts "xavier";

  orin = {
    nvidia-jetpack5 = mkJetPackPackageSet "cudaPackages_11_4" "8.7";
    nvidia-jetpack6 = mkJetPackPackageSet "cudaPackages_12_6" "8.7";

    # Soon (JetPack 7.2)...
    # nvidia-jetpack7 = mkJetPackPackageSet "cudaPackages_13_2" "8.7";
  } // getFlasherScripts "orin";

  thor = {
    nvidia-jetpack7 = mkJetPackPackageSet "cudaPackages_13_0" "11.0";
  } // getFlasherScripts "thor";
}
