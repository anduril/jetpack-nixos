{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types;

  cfg = config.services.nvpmodel;
in
{
  options = {
    services.nvpmodel = {
      enable = mkEnableOption "NVPModel";

      configFile = mkOption {
        description = "config file name from l4t-nvpmodel package to use";
        type = types.path;
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
        ExecStart = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/bin/nvpmodel -f ${cfg.configFile}" + lib.optionalString (cfg.profileNumber != null) " -m ${builtins.toString cfg.profileNumber}";
      };
      wantedBy = [ "multi-user.target" ];
    };

    environment.etc."nvpmodel.conf".source = cfg.configFile;
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
