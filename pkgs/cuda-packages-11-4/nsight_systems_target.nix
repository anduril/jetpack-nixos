{ nvidia-jetpack }:
let
  finalAttrs = {
    pname = "nsight-systems-target";
    version = "2024.5.4";
    srcs = [ nvidia-jetpack.debs.common."nsight-systems-${finalAttrs.version}".src ];
    preDebNormalization =
      let
        # Everything is deeply nested in opt, so we need to move it to the top-level.
        mkPreNorm = arch: ''
          pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null
          mv --verbose --no-clobber "$PWD/opt/nvidia/nsight-systems/${finalAttrs.version}/${arch}" "$PWD/${arch}"
          nixLog "removing $PWD/opt"
          rm --recursive --dir "$PWD/opt" || {
            nixErrorLog "$PWD/opt contains non-empty directories: $(ls -laR "$PWD/opt")"
            exit 1
          }
          # nsys requires that it remains under its original directory so symlink instead of copying
          # things out
          mkdir -p bin
          ln -sfv ../${arch}/nsys ./bin/nsys
          ln -sfv ../${arch}/nsys-launcher ./bin/nsys-launcher
          popd >/dev/null
        '';
      in
      mkPreNorm "target-linux-tegra-armv8";
    meta.platforms = [ "aarch64-linux" ];
  };
in
nvidia-jetpack.buildFromDebs finalAttrs
