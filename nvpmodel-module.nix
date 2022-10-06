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
        ExecStart = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/bin/nvpmodel -f ${cfg.configFile}" + lib.optionalString (cfg.profileNumber != null) " -m ${builtins.toString cfg.profileNumber}";
        ReadWritePaths = [ "/sys" "/var" ];
        ProtectSystem = "strict";
      };
      wantedBy = [ "multi-user.target" ];
    };

    environment.etc."nvpmodel.conf".source = cfg.configFile;
    environment.etc."nvpmodel".source = "${pkgs.nvidia-jetpack.l4t-nvpmodel}/etc/nvpmodel";

    environment.systemPackages = with pkgs.nvidia-jetpack; [ l4t-nvpmodel ];
  };
}
