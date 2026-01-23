{ nvidia-jetpack }:
let
  finalAttrs = {
    pname = "nsight-compute-target";
    version = "2022.2.1";
    srcs = [ nvidia-jetpack.debs.common."nsight-compute-${finalAttrs.version}".src ];
    preDebNormalization =
      let
        # Everything is deeply nested in opt, so we need to move it to the top-level.
        mkPreNorm = arch: ''
          pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null
          mv --verbose --no-clobber "$PWD/opt/nvidia/nsight-compute/${finalAttrs.version}/target/${arch}" "$PWD/target"
          mv --verbose --no-clobber "$PWD/opt/nvidia/nsight-compute/${finalAttrs.version}/extras" "$PWD/extras"
          mv --verbose --no-clobber "$PWD/opt/nvidia/nsight-compute/${finalAttrs.version}/sections" "$PWD/sections"
          nixLog "removing $PWD/opt"
          rm --recursive --dir "$PWD/opt" || {
            nixErrorLog "$PWD/opt contains non-empty directories: $(ls -laR "$PWD/opt")"
            exit 1
          }
          # ncu requires that it remains under its original directory so symlink instead of copying
          # things out
          mkdir -p bin
          ln -sfv ../target/ncu ./bin/ncu
          popd >/dev/null
        '';
      in
      mkPreNorm "linux-v4l_l4t-t210-a64";
    meta.platforms = [ "aarch64-linux" ];
  };
in
nvidia-jetpack.buildFromDebs finalAttrs
