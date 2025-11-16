{ pkgs, config, lib, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    mkRenamedOptionModule
    types
    ;

  cfg = config.services.nvargus-daemon;
in
{
  imports = [
    (mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "ispPkgs" ] [ "services" "nvargus-daemon" "ispPkgs" ])
  ];

  options = {
    services.nvargus-daemon = {
      enable = mkEnableOption "Argus daemon";

      ispPkgs = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = ''
          The list of packages that contain isp files. This
          will copy any files in the /nvcam directory of each package to the
          /var/nvidia/nvcam directory on the device at boot time.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.nvargus-daemon = {
      enable = true;
      description = "Argus daemon";
      serviceConfig = {
        ExecStart = "${pkgs.nvidia-jetpack.l4t-camera}/bin/nvargus-daemon";
        Restart = "on-failure";
        RestartSec = 4;
      };
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.isp-setup =
      let
        ispHash = builtins.hashString "sha256" (builtins.concatStringsSep "\x1f" cfg.ispPkgs);
        copyCmd = builtins.concatStringsSep "\n" (builtins.map (pkg: "${lib.getExe' pkgs.coreutils "cp"} -r ${pkg}/nvcam/. /var/nvidia/nvcam") cfg.ispPkgs);
        copyISPfiles = pkgs.writeShellScriptBin "copy-isp-files" ''
          if [[ -f "/var/nvidia/nvcam/.version" ]]; then
            curVersion=$(cat /var/nvidia/nvcam/.version)
            if [[ $curVersion == ${ispHash} ]]; then
              exit 0
            fi
            rm -rf /var/nvidia/nvcam
          fi

          ${lib.getExe' pkgs.coreutils "mkdir"} -p /var/nvidia/nvcam
          echo ${ispHash} > /var/nvidia/nvcam/.version
          ${copyCmd}
          ${lib.getExe' pkgs.coreutils "chmod"} -R 644 /var/nvidia/nvcam
        '';
      in
      mkIf (builtins.length cfg.ispPkgs != 0) {
        enable = true;
        description = "Copy ISP files to /var/nvidia/nvcam";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe copyISPfiles;
        };
        wantedBy = [ "multi-user.target" ];
      };
  };
}
