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
  , extraDebNormalization ? ""
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

      runHook debNormalization

      runHook postUnpack
    '';

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

      if [[ -e "$PWD/lib64" ]]; then
        nixErrorLog "TODO(@connorbaker): $PWD/lib64's exists, copy everything into lib and make lib64 a symlink to lib"
        ls -la "$PWD/lib64"
        ls -laR "$PWD/lib64/"
        exit 1
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

      if [[ -d "$PWD/etc/ld.so.conf.d" ]]; then
        rm --recursive --force --verbose "$PWD/etc/ld.so.conf.d"
      fi

      if [[ -f "$PWD/lib/ld.so.conf" ]]; then
        rm --force --verbose "$PWD/lib/ld.so.conf"
      fi

      popd >/dev/null

      ${extraDebNormalization}
    '';
  }
)
