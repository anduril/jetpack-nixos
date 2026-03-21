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

      ftpm = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Add fTPM TA and kernel modules.
          '';
        };
        unsafeInjectEPS = mkEnableOption ''
          fTPM TA and CA have functionality added to inject a custom EPS.
          This is effectively a TPM backdoor, and should only be enabled for testing.
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

    boot.kernelModules = mkIf cfg.ftpm.enable [
      "tpm"
    ];

    boot.initrd.availableKernelModules = mkIf cfg.ftpm.enable [
      "tpm"
      "tpm_ftpm_tee"
    ];

    boot.blacklistedKernelModules = mkIf cfg.ftpm.enable[ "tpm_ftpm_tee" ];

    # Load tpm_ftpm_tee driver after tee-supplicant is ready
    systemd.services.ftpm-driver =
      let
        ftpmDriverScript = pkgs.writeShellScript "ftpm-driver-load" ''
          set -euo pipefail

          ${lib.optionalString cfg.ftpm.unsafeInjectEPS ''
            EPS_FILE="/var/lib/unsafeInjectEPS.hex"
            EPS_SIZE=64  # 64 bytes

            # Generate random EPS if it doesn't exist
            if [ ! -f "''$EPS_FILE" ]; then
              echo "Generating random EPS for fTPM..."
              mkdir -p "''$(dirname "''$EPS_FILE")"

              # Generate 64 random bytes and convert to hex with 0x prefix
              EPS_HEX="0x''$(${pkgs.coreutils}/bin/dd if=/dev/urandom bs=1 count=''$EPS_SIZE 2>/dev/null | ${pkgs.xxd}/bin/xxd -p -c 256)"

              # Save to file
              echo "''$EPS_HEX" > "''$EPS_FILE"
              chmod 600 "''$EPS_FILE"

              echo "EPS saved to ''$EPS_FILE"
            else
              echo "Using existing EPS from ''$EPS_FILE"
            fi

            # Inject EPS before driver loads (which triggers fTPM manufacture)
            EPS_VALUE=''$(cat "''$EPS_FILE")
            echo "Injecting EPS into fTPM..."
            ${pkgs.nvidia-jetpack.tosImage.fTpmHelperTa}/bin/nvftpm-helper-app -g "''$EPS_VALUE"
            echo "EPS injection complete"
          ''}

          # Load the fTPM driver
          echo "Loading tpm_ftpm_tee driver..."
          ${pkgs.kmod}/bin/modprobe tpm_ftpm_tee
        '';
      in
      mkIf cfg.ftpm.enable {
        description = "Load fTPM driver after TEE supplicant";
        after = [ "tee-supplicant.service" ];
        requires = [ "tee-supplicant.service" ];
        before = [ "tpm2.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = ftpmDriverScript;
        };
      };


    boot.kernelPatches = mkIf cfg.ftpm.enable [{
      name = "fTPM_tee";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        TCG_TPM = module;
        TCG_FTPM_TEE = module;
      };
      features.fTPM_tee = true;
    }];

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
          Type = "notify";
          ExecStart = "${pkgs.nvidia-jetpack.opteeClient}/bin/tee-supplicant ${args}";
          Restart = "always";
        };
        wantedBy = [ "multi-user.target" ];
      };

    environment.systemPackages = lib.optional cfg.xtest pkgs.nvidia-jetpack.opteeXtest;
  };
}
