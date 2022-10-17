{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types;

  cfg = config.services.nvfancontrol;
in
{
  options = {
    services.nvfancontrol = {
      enable = mkEnableOption "fan control";

      configFile = mkOption {
        description = "config file name from l4t-nvfancontrol package to use";
        type = types.path;
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.nvfancontrol = mkIf cfg.enable {
      enable = true;
      description = "NV Fan control";
      serviceConfig = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/nvfancontrol";
        ExecStart = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/bin/nvfancontrol -f ${cfg.configFile}";
      };
      wantedBy = [ "multi-user.target" ];
    };

    environment.etc."nvfancontrol.conf".source = cfg.configFile;
    environment.etc."nvpower/nvfancontrol".source = "${pkgs.nvidia-jetpack.l4t-nvfancontrol}/etc/nvpower/nvfancontrol";

    environment.systemPackages = with pkgs.nvidia-jetpack; [ l4t-nvfancontrol ];
  };
}
