{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types;

  cfg = config.services.nvpmodel;

  # Experimentally found by doing each of the following for the different power modes
  # rm -f /var/lib/nvpmodel/status && echo gpu_pg_mask_param=4294967295 >/opt/nvidia/l4t-gpusetup/gpu_pg_mask && /nix/store/0000000000-nvidia-l4t-nvpmodel-x.y.z/bin/nvpmodel -f /etc/nvpmodel.conf -m 3 && cat /opt/nvidia/l4t-gpusetup/gpu_pg_mask
  initialGpuPgMaskParamDefaults = {
    "0" = 512;
    "1" = 512;
    "2" = 17353;
    "3" = 17353;
  };
  profileString = toString cfg.profileNumber;


  # This script is based of the nvpower.sh script nvidia provides
  setupConf = pkgs.writeShellScriptBin "setupConf" (''
    compat=$(tr -d '\0' < /proc/device-tree/compatible)

    # xavier doesn't use the compat in the conf file name so we have to hard code the som 
    if [[ "$compat" == *'tegra194'* ]]; then
      if [[ "$compat" == *'agxi'* ]]; then
        device_som="t194_agxi"
      elif [[ "$compat" == *'p3668'* ]]; then
        device_som="t194_p3668"
      else
        device_som="t194"
      fi
    else
      tmp="''${compat#*"+"}"
      tmp2="''${tmp%%"nvidia,"*}"
      device_som="''${tmp2//-/_}"

      echo "Selected device som before hard coding: $device_som"

      # If there are no files that match the compat node use the default nvpower.sh uses
      if [ ! -f ${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_"$device_som".conf ]; then
        if [[ "$device_som" == 'p3767_0005_super' ]]; then
          # The nvpower script maps p3767_0005 -> p3767_0003 so doing the same here
          # for the super variant.
          device_som="p3767_0003_super"
        elif [[ "$device_som" == 'p3767_0005' ]]; then
          # The nvpower script maps p3767_0005 -> p3767_0003 so doing the same here
          # looks to be difference between jp5 and jp6.
          device_som="p3767_0003"
        elif [[ "$compat" == *'tegra234'* ]]; then
          device_som="p3701_0000"
        elif [[ "$compat" == *'tegra264'* ]]; then
          device_som="p3834_0005"
        else
          echo "Unable to find a valid conf file"
          exit 1
        fi
      fi

      echo "Selected device som after hard coding: $device_som"
    fi

    ln -sf ${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_"$device_som".conf /etc/nvpmodel.conf
  ''
  + lib.optionalString (pkgs.nvidia-jetpack.gpuDriver == "openrm") ''
    if [ ! -e /opt/nvidia/l4t-gpusetup/gpu_pg_mask ] ; then
      mkdir -p /opt/nvidia/l4t-gpusetup
      echo "gpu_pg_mask_param=${toString cfg.initialGpuPgMaskParam}" >/opt/nvidia/l4t-gpusetup/gpu_pg_mask
    fi
  '');
in
{
  options = {
    services.nvpmodel = {
      enable = mkEnableOption "NVPModel";

      configFile = mkOption {
        description = "config file name from l4t-nvpmodel package to use";
        default = null;
        type = types.nullOr types.path;
      };

      profileNumber = mkOption {
        description = "ID integer of POWER_MODEL to use from nvpmodel config file. If null, nvpmodel will use the PM_CONFIG DEFAULT setting from the configFile";
        default = null;
        type = types.nullOr types.int;
      };

      # THOR only --
      # Per this thread for some reason the new driver they are using for the GPU doesn't expose
      # a GPU_POWER_GATING sysfs node. And the hack they suggested doesn't work.
      # https://forums.developer.nvidia.com/t/nvpmodel-conf-for-70w-with-jetson-thor/348826/13
      #
      # How nvpmodel now determines the current state of GPU_POWER_GATING is through /opt/nvidia/l4t-gpusetup/gpu_pg_mask
      # This file is read by modprobe.d when loading the GPU drivers to set the GPU_POWER_GATING setting.
      # This file is modified by nvpmodel when changing the power mode. Due to implementation, changing the
      # module paramter at runtime is not supported(?) and requires a reboot.
      #
      # We populate /opt/nvidia/l4t-gpusetup/gpu_pg_mask with default value or with desired initial setting
      # for requested power mode. Further, modeprobe is configured to read /opt/nvidia/l4t-gpusetup/gpu_pg_mask
      # if present or fallback to cfg.initialGpuPgMaskParam.
      initialGpuPgMaskParam = mkOption {
        description = "Initial gpu_pg_mask_param to use during *first* boot of a NixOS system";
        default = 4294967295;
        internal = true;
        type = types.int;
      };
    };
  };

  config = mkIf cfg.enable {
    # https://developer.ridgerun.com/wiki/index.php/Xavier/JetPack_5.0.2/Performance_Tuning
    systemd.services.nvpmodel = mkIf cfg.enable {
      enable = true;
      description = "Set NVPModel power profile";
      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = "2s";
        ExecStartPre = mkIf (cfg.configFile == null) (lib.getExe setupConf);
        ExecStart = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/bin/nvpmodel -f /etc/nvpmodel.conf" + lib.optionalString (cfg.profileNumber != null) " -m ${builtins.toString cfg.profileNumber}";
      };
      wantedBy = [ "multi-user.target" ];
    };

    environment.etc."nvpmodel.conf" = mkIf (cfg.configFile != null) {
      source = cfg.configFile;
    };
    environment.etc."nvpmodel".source = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel";

    environment.systemPackages = with pkgs.nvidia-jetpack; [ l4t-nvpmodel ];

    services.nvpmodel.initialGpuPgMaskParam = lib.mkIf (cfg.profileNumber != null && builtins.hasAttr profileString initialGpuPgMaskParamDefaults) (lib.mkDefault (
      builtins.getAttr profileString initialGpuPgMaskParamDefaults
    ));
  };
}
