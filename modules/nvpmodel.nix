{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types;

  cfg = config.services.nvpmodel;

  # This script is based of the nvpower.sh script nvidia provides
  setupConf = pkgs.writeShellScriptBin "setupConf" ''
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
        if [[ "$device_som" == 'p3767_0005' ]]; then
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

    ln -s ${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel/nvpmodel_"$device_som".conf /etc/nvpmodel.conf
  '';
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
    # Need this hack otherwise setting the mode requires a reboot on JP7 thor
    #
    # Per this thread for some reason the new driver they are using for the GPU doesn't expose
    # a GPU_POWER_GATING sysfs node. And the hack they suggested doesn't work.
    # https://forums.developer.nvidia.com/t/nvpmodel-conf-for-70w-with-jetson-thor/348826/13
    #
    # How nvpmodel now determines the current state of GPU_POWER_GATING is through the /etc/modprobe.d conf files.
    # You might think wow that seems strange because you can change this file at runtime and set a different gpu_pg_mask
    # and then change modes without a reboot. This works and seems to break the rules in the note here
    # https://docs.nvidia.com/jetson/archives/r38.2/DeveloperGuide/SD/PlatformPowerAndPerformance/JetsonThor.html#power-mode-controls
    #
    # The reason thor was failing to set a power mode is because nvpmodel ignores symlinks which all of the NixOS kernel module confs are.
    # Since they symlink back to the nix store.
    # newfstatat(AT_FDCWD, "/etc/modprobe.d/nixos.conf", {st_mode=S_IFLNK|0777, st_size=33, ...}, AT_SYMLINK_NOFOLLOW) = 0
    #
    # To fix this we drop a hardlink for this option at /etc/modprobe.d. Setting the value to -1 allows nvpmodel to overwrite
    # the conf file on first boot.
    environment.etc."NVreg_TegraGpuPgMask.conf" = mkIf (config.hardware.nvidia-jetpack.majorVersion == "7") {
      target = "modprobe.d/NVreg_TegraGpuPgMask.conf";
      text = "options nvidia NVreg_TegraGpuPgMask=-1";
      mode = "0644";
    };

    environment.systemPackages = with pkgs.nvidia-jetpack; [ l4t-nvpmodel ];
  };
}
