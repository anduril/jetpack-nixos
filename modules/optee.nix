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

  inherit (pkgs.nvidia-jetpack) l4tAtLeast l4tOlder;

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
          default = false;
          description = ''
            Enable fTPM (Firmware TPM) support. Builds the MS TPM 2.0
            reference TA and the fTPM helper TA, embeds them in the OP-TEE
            tos.img firmware, and loads the tpm_ftpm_tee kernel driver
            after tee-supplicant is ready. Toggling this option requires
            re-flashing the platform firmware.

            Currently only supported on l4t r36.x. r35 lacks fTPM source;
            r38 refactored fTPM compilation (see CFG_MS_TPM_20_REF) and is
            not yet wired up here.
          '';
        };

        measuredBoot = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Enable measured-boot support. Sets CFG_TA_MEASURED_BOOT in the
            MS TPM 2.0 reference TA build and CFG_CORE_TPM_EVENT_LOG in
            OP-TEE OS.
          '';
        };

        taLogLevel = mkOption {
          type = types.int;
          default = 0;
          description = ''
            CFG_TA_LOG_LEVEL passed to the MS TPM 2.0 reference TA build.
            Independent from
            hardware.nvidia-jetpack.firmware.optee.taLogLevel.
          '';
        };

        unsecureInjectEPS = {
          enable = mkEnableOption ''
            unsecure EPS injection. The fTPM TA exposes functionality to
            inject a custom Endorsement Primary Seed (EPS). This is
            effectively a TPM backdoor and should ONLY be used for testing
          '';

          value = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "0xdeadbeef...";
            description = ''
              Specific EPS value (64-byte hex string with 0x prefix) to
              inject. If null, a random EPS is generated on first boot
              and persisted to /var/lib/unsecureInjectEPS.hex.
            '';
          };
        };
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

  config = mkIf config.hardware.nvidia-jetpack.enable (lib.mkMerge [
    {
      assertions = [{
        # TODO: extend to r38 once fTPM is wired up via CFG_MS_TPM_20_REF.
        assertion = !cfg.ftpm.enable || (l4tAtLeast "36" && l4tOlder "38");
        message = ''
          hardware.nvidia-jetpack.firmware.optee.ftpm.enable currently
          requires l4t r36.x. r35 lacks fTPM source; r38 refactored fTPM
          compilation to use the CFG_MS_TPM_20_REF flag and is not yet
          supported here.
        '';
      }];

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
            # tee-supplicant is patched to call sd_notify(READY=1); without
            # NOTIFY_SOCKET this is a harmless no-op for non-systemd users.
            Type = "notify";
            ExecStart = "${pkgs.nvidia-jetpack.opteeClient}/bin/tee-supplicant ${args}";
            Restart = "always";
          };
          wantedBy = [ "multi-user.target" ];
        };

      environment.systemPackages = lib.optional cfg.xtest pkgs.nvidia-jetpack.opteeXtest;
    }

    (mkIf cfg.ftpm.enable {
      boot.kernelModules = [ "tpm" ];
      boot.initrd.availableKernelModules = [ "tpm" "tpm_ftpm_tee" ];
      # tpm_ftpm_tee must load after tee-supplicant is up.
      boot.blacklistedKernelModules = [ "tpm_ftpm_tee" ];

      boot.kernelPatches = [{
        name = "fTPM_tee";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          TCG_TPM = module;
          TCG_FTPM_TEE = module;
        };
        features.fTPM_tee = true;
      }];

      systemd.services.ftpm-driver =
        let
          epsFile = "/var/lib/unsecureInjectEPS.hex";
          helper = "${pkgs.nvidia-jetpack.ftpmHelperTa}/bin/nvftpm-helper-app";

          epsInjectScript =
            if cfg.ftpm.unsecureInjectEPS.value != null then ''
              echo "Injecting configured EPS into fTPM..."
              ${helper} -g ${lib.escapeShellArg cfg.ftpm.unsecureInjectEPS.value}
            '' else ''
              EPS_FILE=${lib.escapeShellArg epsFile}
              EPS_SIZE=64

              if [ ! -f "$EPS_FILE" ]; then
                echo "Generating random EPS for fTPM..."
                mkdir -p "$(dirname "$EPS_FILE")"
                EPS_HEX="0x$(${pkgs.coreutils}/bin/dd if=/dev/urandom bs=1 count=$EPS_SIZE 2>/dev/null | ${pkgs.xxd}/bin/xxd -p -c 256)"
                echo "$EPS_HEX" > "$EPS_FILE"
                chmod 600 "$EPS_FILE"
                echo "EPS saved to $EPS_FILE"
              else
                echo "Using existing EPS from $EPS_FILE"
              fi

              EPS_VALUE=$(cat "$EPS_FILE")
              echo "Injecting EPS into fTPM..."
              ${helper} -g "$EPS_VALUE"
            '';

          script = pkgs.writeShellScript "ftpm-driver-load" ''
            set -euo pipefail

            ${lib.optionalString cfg.ftpm.unsecureInjectEPS.enable epsInjectScript}

            echo "Loading tpm_ftpm_tee driver..."
            ${pkgs.kmod}/bin/modprobe tpm_ftpm_tee
          '';
        in
        {
          description = "Load fTPM driver after TEE supplicant";
          after = [
            "tee-supplicant.service"
            "local-fs.target"
            "systemd-modules-load.service"
          ];
          requires = [ "tee-supplicant.service" ];
          before = [ "tpm2.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = script;
          };
        };
    })
  ]);
}
