{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkBefore
    mkOption
    mkIf
    types
    ;

  cfg = config.hardware.nvidia-jetpack;
in
{
  options = {
    hardware.nvidia-jetpack = {
      configureCuda = mkOption {
        default = config.hardware.graphics.enable;
        defaultText = "config.hardware.graphics.enable";
        type = types.bool;
        description = ''
          Configures the instance of Nixpkgs used for the system closure for Jetson devices.

          When enabled, Nixpkgs is instantiated with `config.cudaSupport` set to `true`, so all packages
          are built with CUDA support enabled. Additionally, `config.cudaCapabilities` is set based on the
          value of `hardware.nvidia-jetpack.som`, producing binaries targeting the specific Jetson SOM.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    # If NixOS has been configured with CUDA support, add additional assertions to make sure CUDA packages
    # being built have a chance of working.
    assertions =
      let
        inherit (pkgs.cudaPackages) cudaMajorMinorVersion cudaAtLeast cudaOlder;
      in
      lib.optionals pkgs.config.cudaSupport [
        {
          assertion = !cudaOlder "11.4";
          message = "JetPack NixOS does not support CUDA 11.3 or earlier: `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
        }
        {
          assertion = cfg.majorVersion == "5" -> (cudaAtLeast "11.4" && cudaOlder "12.3");
          message = "JetPack NixOS 5 supports CUDA 11.4 (natively) - 12.2 (with `cuda_compat`): `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
        }
        {
          assertion = cfg.majorVersion == "6" -> (cudaAtLeast "12.4" && cudaOlder "13.0");
          message = "JetPack NixOS 6 supports CUDA 12.4 (natively) - 12.9 (with `cuda_compat`): `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
        }
        {
          assertion = !cudaAtLeast "13.0";
          message = "JetPack NixOS does not support CUDA 13.0 or later: `pkgs.cudaPackages` has version ${cudaMajorMinorVersion}.";
        }
        {
          assertion = !((lib.hasPrefix "thor" cfg.som) && (config.hardware.nvidia-jetpack.configureCuda || pkgs.config.cudaSupport));
          message = "CUDA 13 support is not available in NixOS 25.05. Please disable CUDA.";
        }
      ];

    hardware.nvidia-jetpack.configureCuda = lib.mkIf (lib.hasPrefix "thor" cfg.som) (lib.mkForce false);

    # Advertise support for CUDA.
    nixpkgs.config = mkIf cfg.configureCuda (mkBefore {
      cudaSupport = true;
      cudaCapabilities =
        let
          isGeneric = cfg.som == "generic";
          isXavier = lib.hasPrefix "xavier-" cfg.som;
          isOrin = lib.hasPrefix "orin-" cfg.som;
        in
        lib.optionals (isXavier || isGeneric) [ "7.2" ] ++ lib.optionals (isOrin || isGeneric) [ "8.7" ];
    });



    # For some unknown reason, the libnvscf.so library has a dlopen call to a hard path:
    # `/usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0`
    # This causes loading errors for libargus applications and the nvargus-daemon.
    # Errors will look like this:
    # SCF: Error NotSupported: Failed to load EGL library
    # To fix this, create a symlink to the correct EGL library in the above directory.
    #
    # An alternative approach would be to wrap the library with an LD_PRELOAD to a dlopen call
    # that replaces the hardcoded path with the correct path.
    # However, since dynamic library symbol lookups start with the calling binary,
    # this override would have to happen at the binary level, which means every binary
    # would need to be wrapped. This is less desirable than simply adding the following symlink.
    # TODO: Repplace with systemd-tmpfiles?
    systemd.services.create-libegl-symlink =
      let
        linkEglLib = pkgs.writeShellScriptBin "link-egl-lib" ''
          ${lib.getExe' pkgs.coreutils "mkdir"} -p /usr/lib/aarch64-linux-gnu/tegra-egl
          ${lib.getExe' pkgs.coreutils "ln"} -s /run/opengl-driver/lib/libEGL_nvidia.so.0 /usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0
        '';
      in
      {
        enable = cfg.configureCuda;
        description = "Create a symlink for libEGL_nvidia.so.0 at /usr/lib/aarch64-linux-gnu/tegra-egl/";
        unitConfig = {
          ConditionPathExists = "!/usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0";
        };
        serviceConfig = {
          type = "oneshot";
          ExecStart = lib.getExe linkEglLib;
        };
        wantedBy = [ "multi-user.target" ];
      };
  };
}
