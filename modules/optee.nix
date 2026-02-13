{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    mkRenamedOptionModule
    types
    ;

  cfg = config.hardware.nvidia-jetpack.firmware.optee;

in
{
  imports = [
    (mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "firmware" "optee" "supplicantExtraArgs" ] [ "hardware" "nvidia-jetpack" "firmware" "optee" "supplicant" "extraArgs" ])
    (mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "firmware" "optee" "trustedApplications" ] [ "hardware" "nvidia-jetpack" "firmware" "optee" "supplicant" "trustedApplications" ])
    (mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "firmware" "optee" "supplicantPlugins" ] [ "hardware" "nvidia-jetpack" "firmware" "optee" "supplicant" "plugins" ])
  ];

  options = {
    hardware.nvidia-jetpack.firmware.optee = {
      supplicant = {
        enable = mkEnableOption "tee-supplicant daemon" // { default = true; };

        extraArgs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Extra arguments to pass to tee-supplicant.
          '';
        };

        trustedApplications = mkOption {
          type = types.listOf types.package;
          default = [ ];
          description = ''
            Trusted applications that will be loaded into the TEE on
            supplicant startup.
          '';
        };

        plugins = mkOption {
          type = types.listOf types.package;
          default = [ ];
          description = ''
            A list of packages containing TEE supplicant plugins. TEE
            supplicant will load each plugin file in the top level of each
            package on startup.
          '';
        };
      };

      pkcs11Support = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Adds OP-TEE's PKCS#11 TA.
        '';
      };

      xtest = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Adds OP-TEE's xtest and related TA/Plugins
        '';
      };

      patches = mkOption {
        type = types.listOf types.path;
        default = [ ];
      };

      extraMakeFlags = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };

      taPublicKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          The public key to build into optee OS that will be used for
          verifying loaded runtime TAs. If not provided, TAs are verified
          with the public key derived from the private key in optee's
          source tree.
        '';
      };

      coreLogLevel = mkOption {
        type = types.int;
        default = 2;
        description = ''
          OP-TEE core log level, corresponds to CFG_TEE_CORE_LOG_LEVEL
        '';
      };

      taLogLevel = mkOption {
        type = types.int;
        default = cfg.coreLogLevel;
        defaultText = "hardware.nvidia-jetpack.firmware.optee.coreLogLevel";
        description = ''
          OP-TEE trusted application log level, corresponds to CFG_TEE_TA_LOG_LEVEL
        '';
      };
    };
  };

  config = mkIf config.hardware.nvidia-jetpack.enable {
    hardware.nvidia-jetpack.firmware.optee.supplicant.trustedApplications =
      lib.optional cfg.pkcs11Support pkgs.nvidia-jetpack.pkcs11Ta
      ++ lib.optional cfg.xtest pkgs.nvidia-jetpack.opteeXtest.tas;

    hardware.nvidia-jetpack.firmware.optee.supplicant.plugins =
      lib.optional cfg.xtest pkgs.nvidia-jetpack.opteeXtest.plugins;

    systemd.services.tee-supplicant =
      let
        teeApplications = pkgs.symlinkJoin {
          name = "tee-applications";
          paths = cfg.supplicant.trustedApplications;
        };

        supplicantPlugins = pkgs.symlinkJoin {
          name = "tee-supplicant-plugins";
          paths = cfg.supplicant.plugins;
        };

        args = lib.escapeShellArgs (
          [
            "--ta-path=${teeApplications}"
            "--plugin-path=${supplicantPlugins}"
          ]
          ++ cfg.supplicant.extraArgs
        );
      in
      mkIf cfg.supplicant.enable {
        description = "Userspace supplicant for OPTEE-OS";
        serviceConfig = {
          ExecStart = "${pkgs.nvidia-jetpack.opteeClient}/bin/tee-supplicant ${args}";
          Restart = "always";
        };
        wantedBy = [ "multi-user.target" ];
      };

    environment.systemPackages = lib.optional cfg.xtest pkgs.nvidia-jetpack.opteeXtest;
  };
}
