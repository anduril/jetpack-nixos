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

  inherit (pkgs.nvidia-jetpack) l4tAtLeast;

  # Shared derivations used by both initrd and normal-root services.
  teeApplications = pkgs.symlinkJoin {
    name = "tee-applications";
    paths = cfg.supplicant.trustedApplications;
  };

  supplicantPlugins = pkgs.symlinkJoin {
    name = "tee-supplicant-plugins";
    paths = cfg.supplicant.plugins;
  };

  fsParentPathArgs = lib.optional (cfg.supplicant.fsParentPath != null)
    "--fs-parent-path=${cfg.supplicant.fsParentPath}";

  supplicantArgs = lib.escapeShellArgs (
    [
      "--ta-path=${teeApplications}"
      "--plugin-path=${supplicantPlugins}"
    ]
    ++ fsParentPathArgs
    ++ cfg.supplicant.extraArgs
  );

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

        earlyBoot = {
          enable = mkEnableOption ''
            starting tee-supplicant in the initrd (stage-1) so the fTPM
            is available before local-fs.target. Required for LUKS
            auto-unlock with fTPM. Mounts the boot partition in the
            initrd for REE_FS secure storage at /boot/OP-TEE/REE-FS/
          '';

          trustedApplications = mkOption {
            type = types.listOf types.package;
            default = cfg.supplicant.trustedApplications;
            defaultText = "supplicant.trustedApplications";
            description = ''
              Trusted applications for the initrd tee-supplicant. Defaults
              to the same list as the normal-root supplicant. Override to
              reduce initrd size by including only what's needed for LUKS.
            '';
          };

          plugins = mkOption {
            type = types.listOf types.package;
            default = cfg.supplicant.plugins;
            defaultText = "supplicant.plugins";
            description = ''
              Plugins for the initrd tee-supplicant. Defaults to the same
              list as the normal-root supplicant. Override to reduce initrd
              size by including only what's needed for LUKS.
            '';
          };
        };

        fsParentPath = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Path passed to tee-supplicant --fs-parent-path for REE_FS
            secure storage location. If null, uses tee-supplicant's
            compiled-in default.
          '';
        };

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

            Supported on l4t r36.x (Orin / t234) and r38.x (Thor / t264).
            r35 lacks fTPM source. On r38, additionally drops the patch
            that force-disables UEFI's fTPM stack (see
            pkgs/uefi-firmware/r38/disable-ftpm.diff) so that UEFI can
            reach the fTPM TA over FF-A.
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
            CFG_TEE_TA_LOG_LEVEL passed to the MS TPM 2.0 reference TA build.
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
              and persisted. Location: /var/lib/optee/ftpm/unsecureInjectEPS.hex
              (normal) or /boot/OP-TEE/unsecureInjectEPS.hex (earlyBoot).
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
      assertions = [
        {
          assertion = !cfg.ftpm.enable || l4tAtLeast "35.5";
          message = ''
            hardware.nvidia-jetpack.firmware.optee.ftpm.enable requires
            l4t >= r35.5.0.
          '';
        }
        {
          assertion = !cfg.ftpm.enable
            || pkgs.nvidia-jetpack.socType == "t234"
            || pkgs.nvidia-jetpack.socType == "t264";
          message = ''
            hardware.nvidia-jetpack.firmware.optee.ftpm.enable requires
            a t234 (Orin) or t264 (Thor) SoC.
            Got: ${pkgs.nvidia-jetpack.socType}
          '';
        }
        {
          assertion = !cfg.supplicant.earlyBoot.enable || cfg.ftpm.enable;
          message = ''
            supplicant.earlyBoot requires ftpm.enable (the initrd
            services are only useful for fTPM-based LUKS unlock).
          '';
        }
        {
          assertion = !cfg.supplicant.earlyBoot.enable
            || config.fileSystems ? "/boot";
          message = ''
            supplicant.earlyBoot requires fileSystems."/boot" to be
            defined. The boot partition is mounted in the initrd for
            OP-TEE REE_FS secure storage (/boot/optee/).
          '';
        }
      ];

      hardware.nvidia-jetpack.firmware.optee.supplicant.trustedApplications =
        lib.optional cfg.pkcs11Support pkgs.nvidia-jetpack.pkcs11Ta
        ++ lib.optional cfg.xtest pkgs.nvidia-jetpack.opteeXtest.tas;

      hardware.nvidia-jetpack.firmware.optee.supplicant.plugins =
        lib.optional cfg.xtest pkgs.nvidia-jetpack.opteeXtest.plugins;

      systemd.services.tee-supplicant = mkIf cfg.supplicant.enable {
        description = "Userspace supplicant for OPTEE-OS";
        unitConfig.DefaultDependencies = false;
        after = [ "local-fs.target" "modprobe@optee.service" ];
        wants = [ "modprobe@optee.service" ];
        before = [ "shutdown.target" ];
        conflicts = [ "shutdown.target" ];
        serviceConfig = {
          Type = "notify";
          ExecStart = "${pkgs.nvidia-jetpack.opteeClient}/bin/tee-supplicant ${supplicantArgs}";
          Restart = "always";
        };
        wantedBy = [ "multi-user.target" ];
      };

      environment.systemPackages = lib.optional cfg.xtest pkgs.nvidia-jetpack.opteeXtest;
    }

    (mkIf cfg.ftpm.enable (
      let
        epsFile =
          if cfg.supplicant.earlyBoot.enable
          then "/boot/OP-TEE/unsecureInjectEPS.hex"
          else "/var/lib/optee/ftpm/unsecureInjectEPS.hex";
        helper = "${pkgs.nvidia-jetpack.ftpmHelperTa}/bin/nvftpm-helper-app";
        # nvftpm-helper-app CLI changed between JetPack releases:
        #   JP5 (r35): -g injects EPS
        #   JP6+ (r36+): -g queries ECID, -m injects EPS
        epsFlag = if l4tAtLeast "36" then "-m" else "-g";

        epsInjectScript = ''
          EPS_FILE=${lib.escapeShellArg epsFile}
          EPS_SIZE=64
          if [ ! -f "$EPS_FILE" ]; then
            ${if cfg.ftpm.unsecureInjectEPS.value != null then ''
              echo "Generating configured EPS for fTPM..."
              EPS_HEX="${lib.escapeShellArg cfg.ftpm.unsecureInjectEPS.value}"
            '' else ''
              echo "Generating random EPS for fTPM..."
              mkdir -p "$(dirname "$EPS_FILE")"
              EPS_HEX="0x$(${pkgs.coreutils}/bin/dd if=/dev/urandom bs=1 count=$EPS_SIZE 2>/dev/null | ${pkgs.xxd}/bin/xxd -p -c 256)"
            ''}
            echo "$EPS_HEX" > "$EPS_FILE"
            chmod 600 "$EPS_FILE"
            echo "EPS saved to $EPS_FILE"
          else
            echo "Using existing EPS from $EPS_FILE"
          fi
          EPS_VALUE=$(cat "$EPS_FILE")
          echo "Injecting EPS into fTPM..."
          ${helper} ${epsFlag} "$EPS_VALUE"
        '';

        startScript = pkgs.writeShellScript "ftpm-driver-load" ''
          set -euo pipefail

          ${lib.optionalString cfg.ftpm.unsecureInjectEPS.enable epsInjectScript}

          echo "Loading tpm_ftpm_tee driver..."
          ${pkgs.kmod}/bin/modprobe tpm_ftpm_tee
        '';

        # Used when earlyBoot is enabled: cycle the module to close the
        # stale TEE session from the initrd supplicant and open a fresh one
        # with the post-switch-root supplicant (cf. OP-TEE issue #5766).
        reloadScript = pkgs.writeShellScript "ftpm-driver-reload" ''
          set -euo pipefail

          echo "Reloading tpm_ftpm_tee (fresh session after switch-root)..."
          ${pkgs.kmod}/bin/modprobe -r tpm_ftpm_tee
          sleep 1
          ${pkgs.kmod}/bin/modprobe tpm_ftpm_tee
        '';

        stopScript = pkgs.writeShellScript "ftpm-driver-unload" ''
          set -euo pipefail

          echo "Unloading tpm_ftpm_tee driver..."
          ${pkgs.kmod}/bin/modprobe -v -r tpm_ftpm_tee
        '';
      in
      {
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

        systemd.services.ftpm-driver = {
          description = "Load fTPM driver after TEE supplicant";
          unitConfig.DefaultDependencies = false;
          after = [
            "tee-supplicant.service"
            "local-fs.target"
            "systemd-modules-load.service"
          ];
          before = [
            "tpm2.target"
            "systemd-tpm2-setup-early.service"
            "systemd-tpm2-setup.service"
            "shutdown.target"
          ];
          conflicts = [ "shutdown.target" ];
          requires = [ "tee-supplicant.service" ];
          wantedBy = [ "tpm2.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart =
              if cfg.supplicant.earlyBoot.enable
              then reloadScript
              else startScript;
            ExecStop = stopScript;
            StateDirectory = "optee/ftpm";
          };
        };
      }
    ))

    # earlyBoot: run tee-supplicant and ftpm-driver in the initrd so
    # /dev/tpm0 is available before local-fs.target (for LUKS unlock).
    (mkIf (cfg.supplicant.earlyBoot.enable && cfg.ftpm.enable) (
      let
        bootFs = config.fileSystems."/boot";

        initrdTeeApplications = pkgs.symlinkJoin {
          name = "tee-applications-initrd";
          paths = cfg.supplicant.earlyBoot.trustedApplications;
        };

        initrdSupplicantPlugins = pkgs.symlinkJoin {
          name = "tee-supplicant-plugins-initrd";
          paths = cfg.supplicant.earlyBoot.plugins;
        };

        initrdSupplicantArgs = lib.escapeShellArgs (
          [
            "--ta-path=${initrdTeeApplications}"
            "--plugin-path=${initrdSupplicantPlugins}"
          ]
          ++ fsParentPathArgs
          ++ cfg.supplicant.extraArgs
        );

        initrdEpsInjectScript = ''
          EPS_FILE="/boot/OP-TEE/unsecureInjectEPS.hex"
          EPS_SIZE=64
          if [ ! -f "$EPS_FILE" ]; then
            ${if cfg.ftpm.unsecureInjectEPS.value != null then ''
              echo "Generating configured EPS for fTPM..."
              EPS_HEX="${lib.escapeShellArg cfg.ftpm.unsecureInjectEPS.value}"
            '' else ''
              echo "Generating random EPS for fTPM..."
              mkdir -p "$(dirname "$EPS_FILE")"
              EPS_HEX="0x$(${pkgs.coreutils}/bin/dd if=/dev/urandom bs=1 count=$EPS_SIZE 2>/dev/null | ${pkgs.xxd}/bin/xxd -p -c 256)"
            ''}
            echo "$EPS_HEX" > "$EPS_FILE"
            chmod 600 "$EPS_FILE"
            echo "EPS saved to $EPS_FILE"
          else
            echo "Using existing EPS from $EPS_FILE"
          fi
          EPS_VALUE=$(cat "$EPS_FILE")
          echo "Injecting EPS into fTPM..."
          ${pkgs.nvidia-jetpack.ftpmHelperTa}/bin/nvftpm-helper-app ${if l4tAtLeast "36" then "-m" else "-g"} "$EPS_VALUE"
        '';

        initrdStartScript = pkgs.writeShellScript "ftpm-driver-load-initrd" ''
          set -euo pipefail

          ${lib.optionalString cfg.ftpm.unsecureInjectEPS.enable initrdEpsInjectScript}

          echo "Loading tpm_ftpm_tee driver..."
          ${pkgs.kmod}/bin/modprobe tpm_ftpm_tee
        '';
      in
      {
        # Force-load optee in initrd so /dev/tee0 appears immediately.
        boot.initrd.kernelModules = [ "optee" ];

        # Default fsParentPath to /boot/OP-TEE/REE-FS when earlyBoot is enabled.
        hardware.nvidia-jetpack.firmware.optee.supplicant.fsParentPath =
          lib.mkDefault "/boot/OP-TEE/REE-FS";

        boot.initrd.systemd = {
          storePaths = [
            "${pkgs.nvidia-jetpack.opteeClient}/bin/tee-supplicant"
            "${initrdTeeApplications}"
            "${initrdSupplicantPlugins}"
            "${pkgs.kmod}/bin/modprobe"
            "${pkgs.nvidia-jetpack.ftpmHelperTa}/bin/nvftpm-helper-app"
            "${initrdStartScript}"
          ] ++ lib.optionals cfg.ftpm.unsecureInjectEPS.enable [
            "${pkgs.coreutils}/bin/dd"
            "${pkgs.xxd}/bin/xxd"
          ];

          # Mount /boot in the initrd for REE_FS secure storage access.
          mounts = [{
            where = "/boot";
            what = bootFs.device;
            type = bootFs.fsType or "vfat";
            options = lib.concatStringsSep "," (bootFs.options or [ ]);
          }];

          services.tee-supplicant = {
            description = "Userspace supplicant for OPTEE-OS (initrd)";
            unitConfig.DefaultDependencies = false;
            after = [ "boot.mount" "systemd-modules-load.service" ];
            requires = [ "boot.mount" ];
            before = [ "shutdown.target" ];
            conflicts = [ "shutdown.target" ];
            serviceConfig = {
              Type = "notify";
              ExecStart = "${pkgs.nvidia-jetpack.opteeClient}/bin/tee-supplicant ${initrdSupplicantArgs}";
              Restart = "always";
            };
            wantedBy = [ "sysinit.target" ];
          };

          services.ftpm-driver = {
            description = "Load fTPM driver (initrd)";
            unitConfig.DefaultDependencies = false;
            after = [ "tee-supplicant.service" "boot.mount" ];
            before = [
              "tpm2.target"
              "systemd-tpm2-setup-early.service"
              "systemd-tpm2-setup.service"
              "shutdown.target"
            ];
            conflicts = [ "shutdown.target" ];
            requires = [ "tee-supplicant.service" ];
            wantedBy = [ "tpm2.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = initrdStartScript;
              # Unload module during switch-root cleanup so /dev/tpm0
              # disappears. Prevents stale session from being probed by
              # udev/systemd-tpm2-setup before the normal ftpm-driver
              # can establish a fresh session post-switch-root.
              ExecStop = "${pkgs.kmod}/bin/modprobe -r tpm_ftpm_tee";
            };
          };
        };
      }
    ))
  ]);
}
