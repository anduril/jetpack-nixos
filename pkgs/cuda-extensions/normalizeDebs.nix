{ cudaMajorMinorVersion
, dpkg
, lib
, srcOnly
, stdenvNoCC
}:
let
  inherit (stdenvNoCC.hostPlatform) parsed;

  # aarch64-linux, etc.
  targetStringDouble = "${parsed.cpu.name}-${parsed.kernel.name}";

  # aarch64-linux-gnu, etc.
  targetStringTriple = "${targetStringDouble}-${parsed.abi.name}";
in
# Give a list of debs (`srcs`), unpacks and normalizes the resulting directory structure so the result can be used
  # with upstream's buildRedist.
lib.makeOverridable (
  { srcs
  , preDebNormalization ? ""
  , postDebNormalization ? ""
  , pname
  , version
  }:
  srcOnly {
    __structuredAttrs = true;
    strictDeps = true;

    stdenv = stdenvNoCC;

    inherit srcs pname version;

    nativeBuildInputs = [ dpkg ];

    # Set sourceRoot when we use a custom unpackPhase
    sourceRoot = "source";

    unpackPhase = ''
      runHook preUnpack

      for src in "''${srcs[@]}"; do
        nixLog "unpacking debian archive $src to $sourceRoot"
        dpkg-deb -x "$src" "$sourceRoot"
      done
      unset -v src

      runHook preDebNormalization

      runHook debNormalization

      runHook postDebNormalization

      runHook postUnpack
    '';

    inherit preDebNormalization postDebNormalization;

    debNormalization = ''
      pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null

      if [[ -e "$PWD/usr" ]]; then
        pushd "$PWD/usr" >/dev/null

        if [[ -e "$PWD/local/cuda-${cudaMajorMinorVersion}" ]]; then
          pushd "$PWD/local/cuda-${cudaMajorMinorVersion}" >/dev/null

          if [[ -e "$PWD/targets/${targetStringDouble}" ]]; then
            pushd "$PWD/targets/${targetStringDouble}" >/dev/null

            mv \
              --verbose \
              --no-clobber \
              --target-directory "$NIX_BUILD_TOP/$sourceRoot" \
              "$PWD"/*

            popd >/dev/null

            nixLog "removing $PWD/targets"
            rm --recursive --dir "$PWD/targets" || {
              nixErrorLog "$PWD/targets contains non-empty directories: $(ls -laR "$PWD/targets")"
              exit 1
            }
          fi

          mv \
            --verbose \
            --no-clobber \
            --target-directory "$NIX_BUILD_TOP/$sourceRoot" \
            "$PWD"/*

          popd >/dev/null

          nixLog "removing $PWD/local"
          rm --recursive --dir "$PWD/local" || {
            nixErrorLog "$PWD/local contains non-empty directories: $(ls -laR "$PWD/local")"
            exit 1
          }
        fi

        # These two are expected to be mutually exclusive
        dir=""
        for dir in *; do
          if [[ -d "$PWD/$dir/${targetStringTriple}" ]]; then
            mkdir -p "$NIX_BUILD_TOP/$sourceRoot/$dir"
            mv \
              --verbose \
              --no-clobber \
              --target-directory "$NIX_BUILD_TOP/$sourceRoot/$dir" \
              "$PWD/$dir/${targetStringTriple}"/*
          else
            mv \
              --verbose \
              --no-clobber \
              --target-directory "$NIX_BUILD_TOP/$sourceRoot" \
              "$PWD/$dir"
          fi
        done
        unset -v dir

        popd >/dev/null

        nixLog "removing $PWD/usr"
        rm --recursive --dir "$PWD/usr" || {
          nixErrorLog "$PWD/usr contains non-empty directories: $(ls -laR "$PWD/usr")"
          exit 1
        }
      fi

      if [[ -d "$PWD/lib64" ]]; then
        if [[ ! -e "$PWD/lib" ]]; then
          nixLog "renaming $PWD/lib64 to $PWD/lib"
          mv \
            --verbose \
            --no-clobber \
            "$PWD/lib64" \
            "$PWD/lib"
        else
          nixLog "moving contents of $PWD/lib64 to $PWD/lib"
          mv \
            --verbose \
            --no-clobber \
            --target-directory "$PWD/lib" \
            "$PWD/lib64"/*
          nixLog "removing $PWD/lib64"
          rm --recursive --dir "$PWD/lib64" || {
            nixErrorLog "$PWD/lib64 contains non-empty directories: $(ls -laR "$PWD/lib64")"
            exit 1
          }
        fi
      elif [[ -d "$PWD/lib" ]]; then
        if [[ -L "$PWD/lib64" ]]; then
          nixLog "removing existing symlink $PWD/lib64"
          rm "$PWD/lib64"
        fi
        if [[ -n "$(find "$PWD/lib" -not \( -path "$PWD/lib/stubs" -prune \) -name \*.so)" ]] ; then
          nixLog "symlinking $PWD/lib64 -> $PWD/lib"
          ln -rs "$PWD/lib" "$PWD/lib64"
        fi
      fi

      if [[ -d "$PWD/sbin" ]]; then
        if [[ -n "$(ls "$PWD/sbin")" ]]; then
          mkdir -p "$PWD/bin"
          mv \
            --verbose \
            --no-clobber \
            --target-directory "$PWD/bin" \
            "$PWD/sbin"/*
        fi
        rm --recursive --dir "$PWD/sbin" || {
          nixErrorLog "$PWD/sbin contains non-empty directories: $(ls -laR "$PWD/sbin")"
          exit 1
        }
      fi

      if [[ -d "$PWD/lib" ]]; then
        dir=""
        for dir in nvidia tegra; do
          # NOTE: Check if the directory is empty in the case it was symlinked to/from and we've already moved everything from it.
          if [[ -e "$PWD/lib/$dir" && -n "$(ls "$PWD/lib/$dir/")" ]]; then
            # NOTE: We do want to clobber, since existing entries in lib are usually symlinks to these files.
            mv \
              --verbose \
              --target-directory "$PWD/lib" \
              "$PWD/lib/$dir"/*
            rm --recursive --dir "$PWD/lib/$dir" || {
              nixErrorLog "$PWD/lib/$dir contains non-empty directories: $(ls -laR "$PWD/lib/$dir")"
              exit 1
            }
          fi
          if [[ -L "$PWD/lib/$dir" ]]; then
            rm "$PWD/lib/$dir"
          fi
        done
        unset -v dir
      fi

      # General cleanup. Since we run with --force, missing files/directories do not cause errors.
      rm --recursive --force --verbose "$PWD/etc/ld.so.conf.d"
      rm --recursive --force --verbose "$PWD/etc/dpkg"
      rm --force --verbose "$PWD/lib/ld.so.conf"

      popd >/dev/null
    '';
  }
)
