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
      # Remove a directory whose payload was moved out by an earlier mv,
      # tolerating dangling symlinks and empty intermediate dirs (deb-internal
      # navigation aids, not real content). Fails loud if anything else is
      # left, surfacing silent-drop bugs at packaging time.
      pruneEmptied() {
        local target="$1"
        # Some debs ship $target itself as a symlink (e.g. vpi2's
        # lib64 -> lib/aarch64-linux-gnu)
        if [[ -L "$target" ]]; then
          nixLog "removing symlink $target"
          rm "$target"
          return 0
        fi
        [[ -e "$target" ]] || return 0
        nixLog "removing $target"
        find "$target" -type l -! -exec test -e {} \; -delete
        find "$target" -depth -type d -empty -delete
        if [[ -e "$target" ]]; then
          nixErrorLog "$target contains unhandled content after debNormalization: $(ls -laR "$target")"
          exit 1
        fi
      }

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

            pruneEmptied "$PWD/targets"
          fi

          mv \
            --verbose \
            --no-clobber \
            --target-directory "$NIX_BUILD_TOP/$sourceRoot" \
            "$PWD"/*

          popd >/dev/null

          pruneEmptied "$PWD/local"
        fi

        # Debs ship a mix of layouts under usr/<dir>/ (e.g. usr/lib/):
        # - triplet only        (aarch64-linux-gnu/<files>)
        # - siblings only       (pkgconfig/, xorg/, python3/, ...)
        # - both                (triplet + siblings, e.g. nvidia-l4t-core)
        # Flatten the triplet up one level, then merge siblings into the
        # same target — handling all three layouts with one code path.
        dir=""
        for dir in *; do
          mkdir -p "$NIX_BUILD_TOP/$sourceRoot/$dir"
          if [[ -d "$PWD/$dir/${targetStringTriple}" ]]; then
            if [[ -n "$(ls -A "$PWD/$dir/${targetStringTriple}")" ]]; then
              mv \
                --verbose \
                --no-clobber \
                --target-directory "$NIX_BUILD_TOP/$sourceRoot/$dir" \
                "$PWD/$dir/${targetStringTriple}"/*
            fi
            rmdir "$PWD/$dir/${targetStringTriple}"
          fi
          if [[ -n "$(ls -A "$PWD/$dir")" ]]; then
            mv \
              --verbose \
              --no-clobber \
              --target-directory "$NIX_BUILD_TOP/$sourceRoot/$dir" \
              "$PWD/$dir"/*
          fi
          rmdir "$PWD/$dir"
        done
        unset -v dir

        popd >/dev/null

        pruneEmptied "$PWD/usr"
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
          pruneEmptied "$PWD/lib64"
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
        pruneEmptied "$PWD/sbin"
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
            pruneEmptied "$PWD/lib/$dir"
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
