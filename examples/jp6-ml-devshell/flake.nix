{
  description = "JetPack 6 devShell with CUDA 12.6 (see jetpack-nixos#427, #507)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    jetpack-nixos.url = "github:anduril/jetpack-nixos";
    jetpack-nixos.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { jetpack-nixos, nixpkgs, ... }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          cudaSupport = true;
          cudaCapabilities = [ "8.7" ];
        };
        overlays = [
          jetpack-nixos.overlays.default
          (final: _: {
            cudaPackages = final.cudaPackages_12_6;
          })
        ];
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        name = "jp6-ml-devshell";

        packages = with pkgs.cudaPackages; [
          cuda_cudart
          libcublas
          cudnn
          libcufft
          libcurand
          libcusparse
          libcusolver
          cuda_nvrtc
          libnvjitlink
          cuda_cupti
        ];

        shellHook = ''
          echo "JetPack 6 ML devShell — CUDA ${pkgs.cudaPackages.cudaMajorMinorVersion}"
          echo "libcublas: ${pkgs.cudaPackages.libcublas.name}"
          echo ""
          echo "Smoke: nix run .#smoke-eval"
        '';
      };

      packages.${system}.smoke-eval = pkgs.writeShellScriptBin "jp6-cuda-smoke" ''
        set -euo pipefail
        echo "libcublas derivation: ${pkgs.cudaPackages.libcublas.name}"
        test -e "${pkgs.lib.getLib pkgs.cudaPackages.libcublas}/lib/libcublas.so" \
          || test -n "$(find "${pkgs.lib.getLib pkgs.cudaPackages.libcublas}/lib" -name 'libcublas.so*' -print -quit)"
        echo "OK: libcublas present in store"
      '';
    };
}
