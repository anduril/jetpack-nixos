{ buildFromDebs, debs }:
let
  finalAttrs = {
    pname = "nsight-systems-target";
    version = "2024.5.4";
    srcs = debs.common."nsight-systems-${finalAttrs.version}".src;
    postPatch = ''
      cp -r "opt/nvidia/nsight-systems/${finalAttrs.version}/target-linux-tegra-armv8" .
      rm -rf opt

      # nsys requires that it remains under its original directory so symlink instead of copying
      # things out
      mkdir -p bin
      ln -sfv ../target-linux-tegra-armv8/nsys ./bin/nsys
      ln -sfv ../target-linux-tegra-armv8/nsys-launcher ./bin/nsys-launcher
    '';
    meta.platforms = [ "aarch64-linux" ];
  };
in
buildFromDebs finalAttrs
