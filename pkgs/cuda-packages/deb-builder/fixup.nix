# NOTE: All fixups must be at least binary functions to avoid callPackage adding override attributes.
# Taken largely from
# https://github.com/ConnorBaker/cuda-packages/blob/3fdad92cf320274cf24c87a30e3498a5d9fad18e/pkgs/development/cuda-modules/packages/common/redist-builder.nix
{ autoAddDriverRunpath
, autoPatchelfHook
, config
, cudaConfig
, cudaMajorMinorVersion
, dpkg
, flags
, lib
, markForCudatoolkitRootHook
, stdenv
}:
let
  inherit (cudaConfig) hostRedistSystem;
  inherit (lib) licenses sourceTypes;
  inherit (lib.attrsets) attrValues;
  inherit (lib.lists)
    any
    elem
    findFirstIndex
    intersectLists
    optionals
    tail
    unique
    ;
  inherit (lib.strings) concatMapStringsSep;
  inherit (lib.trivial) flip id warnIfNot;
  inherit (stdenv.hostPlatform) parsed;

  hasAnyTrueValue = attrs: any id (attrValues attrs);
in
# We need finalAttrs, so even if prevAttrs isn't used we still need to take it as an argument (see https://noogle.dev/f/lib/fixedPoints/toExtension).
finalAttrs: _:
let
  inherit (finalAttrs.passthru) debBuilderArgs;
  hasOutput = flip elem finalAttrs.outputs;
in
{
  __structuredAttrs = true;
  strictDeps = true;

  pname = debBuilderArgs.packageName;
  inherit (debBuilderArgs.releaseInfo) version;

  # lists.intersectLists iterates over the second list, checking if the elements are in the first list.
  # As such, the order of the output is dictated by the order of the second list.
  outputs = intersectLists debBuilderArgs.outputs finalAttrs.passthru.expectedOutputs;

  # NOTE: Because the `dev` output is special in Nixpkgs -- make-derivation.nix uses it as the default if
  # it is present -- we must ensure that it brings in the expected dependencies. For us, this means that `dev`
  # should include `bin`, `include`, and `lib` -- `static` is notably absent because it is quite large.
  # We do not include `stubs`, as a number of packages contain stubs for libraries they already ship with!
  # Only a few, like cuda_cudart, actually provide stubs for libraries we're missing.
  # As such, these packages should override propagatedBuildOutputs to add `stubs`.
  propagatedBuildOutputs = intersectLists [
    "bin"
    "include"
    "lib"
  ]
    finalAttrs.outputs;

  # We have a separate output for include files; don't use the dev output.
  # NOTE: We must set outputInclude carefully to ensure we get fallback to other outputs if the `include` output
  # doesn't exist.
  outputInclude =
    if hasOutput "include" then
      "include"
    else if hasOutput "dev" then
      "dev"
    else
      "out";

  outputStubs = if hasOutput "stubs" then "stubs" else "out";

  outputStatic = if hasOutput "static" then "static" else "out";

  srcs = debBuilderArgs.debs;

  # Set sourceRoot when we use a custom unpackPhase
  sourceRoot = "source";

  unpackPhase = ''
    runHook preUnpack

    for src in "''${srcs[@]}"; do
      echo "unpacking debian archive $src to $NIX_BUILD_TOP/$sourceRoot"
      dpkg-deb -x "$src" "$NIX_BUILD_TOP/$sourceRoot"
    done
    unset -v src

    runHook debNormalization

    runHook postUnpack
  '';

  debNormalization = ''
    pushd "$NIX_BUILD_TOP/$sourceRoot"

    if [[ -e "$PWD/usr" ]]; then
      pushd "$PWD/usr"

      if [[ -e "$PWD/local/cuda-${cudaMajorMinorVersion}" ]]; then
        pushd "$PWD/local/cuda-${cudaMajorMinorVersion}"

        if [[ -e "$PWD/targets/${debBuilderArgs.targetStringDouble}" ]]; then
          pushd "$PWD/targets/${debBuilderArgs.targetStringDouble}"

          mv \
            --verbose \
            --no-clobber \
            --target-directory "$NIX_BUILD_TOP/$sourceRoot" \
            "$PWD"/*

          popd

          echo "removing $PWD/targets"
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

        popd

        echo "removing $PWD/local"
        rm --recursive --dir "$PWD/local" || {
          nixErrorLog "$PWD/local contains non-empty directories: $(ls -laR "$PWD/local")"
          exit 1
        }
      fi

      # These two are expected to be mutually exclusive
      dir=""
      for dir in *; do
        if [[ -d "$PWD/$dir/${debBuilderArgs.targetStringTriple}" ]]; then
          mkdir -p "$NIX_BUILD_TOP/$sourceRoot/$dir"
          mv \
            --verbose \
            --no-clobber \
            --target-directory "$NIX_BUILD_TOP/$sourceRoot/$dir" \
            "$PWD/$dir/${debBuilderArgs.targetStringTriple}"/*
        else
          mv \
            --verbose \
            --no-clobber \
            --target-directory "$NIX_BUILD_TOP/$sourceRoot" \
            "$PWD/$dir"
        fi
      done
      unset -v dir

      popd

      echo "removing $PWD/usr"
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
        echo "removing existing symlink $PWD/lib64"
        rm "$PWD/lib64"
      fi
      echo "symlinking $PWD/lib64 -> $PWD/lib"
      ln -rs "$PWD/lib" "$PWD/lib64"
    fi

    if [[ -d "$PWD/etc/ld.so.conf.d" ]]; then
      rm --recursive --force --verbose "$PWD/etc/ld.so.conf.d"
    fi

    if [[ -f "$PWD/lib/ld.so.conf" ]]; then
      rm --force --verbose "$PWD/lib/ld.so.conf"
    fi

    popd
  '';

  postPatch =
    # Pkg-config's setup hook expects configuration files in $out/share/pkgconfig
    ''
      for path in "$NIX_BUILD_TOP/$sourceRoot"/{pkg-config,pkgconfig}; do
        [[ -d $path ]] || continue
        mkdir -p "$NIX_BUILD_TOP/$sourceRoot/share/pkgconfig"
        mv \
          --verbose \
          --no-clobber \
          --target-directory "$NIX_BUILD_TOP/$sourceRoot/share/pkgconfig" \
          "$path"/*
        rm --recursive --dir "$path" || {
          nixErrorLog "$path contains non-empty directories: $(ls -laR "$path")"
          exit 1
        }
      done
      unset -v path
    ''
    # Rewrite FHS paths with store paths
    # NOTE: output* fall back to out if the corresponding output isn't defined.
    + ''
      for pc in "$NIX_BUILD_TOP/$sourceRoot"/share/pkgconfig/*.pc; do
        echo "patching $pc"
        sed -i \
          -e "s|^cudaroot\s*=.*\$|cudaroot=''${!outputDev:?}|" \
          -e "s|^libdir\s*=.*/lib\$|libdir=''${!outputLib:?}/lib|" \
          -e "s|^includedir\s*=.*/include\$|includedir=''${!outputDev:?}/include|" \
          "$pc"
      done
      unset -v pc
    ''
    # Generate unversioned names.
    # E.g. cuda-11.8.pc -> cuda.pc
    # TODO(@connorbaker): Are the arguments here flipped? Isn't is target then link name?
    + ''
      for pc in "$NIX_BUILD_TOP/$sourceRoot"/share/pkgconfig/*-"${cudaMajorMinorVersion}.pc"; do
        echo "creating unversioned symlink for $pc"
        ln -s "$(basename "$pc")" "''${pc%-${cudaMajorMinorVersion}.pc}".pc
      done
      unset -v pc
    '';

  # NOTE: Even though there's no actual buildPhase going on here, the derivations of the
  # redistributables are sensitive to the compiler flags provided to stdenv. The patchelf package
  # is sensitive to the compiler flags provided to stdenv, and we depend on it. As such, we are
  # also sensitive to the compiler flags provided to stdenv.
  # NOTE: We do need some other phases, like configurePhase, so the multiple-output setup hook works.
  dontBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
    # This hook will make sure libcuda can be found
    # in typically /lib/opengl-driver by adding that
    # directory to the rpath of all ELF binaries.
    # Check e.g. with `patchelf --print-rpath path/to/my/binary
    autoAddDriverRunpath
    dpkg
    markForCudatoolkitRootHook
  ];

  buildInputs = [
    # autoPatchelfHook will search for a libstdc++ and we're giving it
    # one that is compatible with the rest of nixpkgs, even when
    # nvcc forces us to use an older gcc
    # NB: We don't actually know if this is the right thing to do
    # NOTE: Not all packages actually need this, but it's easier to just add it than create overrides for nearly all
    # of them.
    stdenv.cc.cc.lib
  ];

  # Picked up by autoPatchelf
  # Needed e.g. for libnvrtc to locate (dlopen) libnvrtc-builtins
  appendRunpaths = [ "$ORIGIN" ];

  # NOTE: We don't need to check for dev or doc, because those outputs are handled by
  # the multiple-outputs setup hook.
  # NOTE: moveToOutput operates on all outputs:
  # https://github.com/NixOS/nixpkgs/blob/2920b6fc16a9ed5d51429e94238b28306ceda79e/pkgs/build-support/setup-hooks/multiple-outputs.sh#L105-L107
  installPhase =
    let
      mkMoveToOutputCommand =
        output:
        let
          template = pattern: ''
            moveToOutput "${pattern}" "${"$" + output}"
          '';
          patterns = finalAttrs.passthru.outputToPatterns.${output} or [ ];
        in
        concatMapStringsSep "\n" template patterns;
    in
    # Pre-install hook
    ''
      runHook preInstall
    ''
    # Create the primary output, out, and move the other outputs into it.
    + ''
      mkdir -p "$out"
      echo "moving tree to output out"
      mv * "$out"
    ''
    # Move the outputs into their respective outputs.
    + ''
      ${concatMapStringsSep "\n" mkMoveToOutputCommand (tail finalAttrs.outputs)}
    ''
    # Post-install hook
    + ''
      runHook postInstall
    '';

  doInstallCheck = true;
  allowFHSReferences = false;
  postInstallCheck = ''
    if [[ -z "''${allowFHSReferences-}" ]]; then
      echo "Checking for FHS references"
      firstMatches="$(grep --max-count=5 --recursive --exclude=LICENSE /usr/ "''${outputPaths[@]}")" || true
      if [[ -n "$firstMatches" ]]; then
        echo "ERROR: Detected the references to /usr: $firstMatches"
        exit 1
      fi
      unset -v firstMatches
    fi

    for output in $(getAllOutputNames); do
      [[ "''${!output:?}" == "out" ]] && continue
      echo "Checking if "''${!output:?}" contains files..."
      case "$(find "''${!output:?}" -mindepth 1 -maxdepth 1 -type d)" in
      "" | "''${!output:?}/nix-support/")
        nixErrorLog "output $output is empty (excluding nix-support)!"
        nixErrorLog "this typically indicates a failure in patterns or files matched and moved or move order"
        ls -laR "''${!output:?}"
        exit 1
        ;;
      *) continue ;;
      esac
    done
    unset -v output
  '';

  # TODO(@connorbaker): https://github.com/NixOS/nixpkgs/issues/323126.
  # _multioutPropagateDev() currently expects a space-separated string rather than an array.
  # Because it is a postFixup hook, we correct it in preFixup.
  preFixup = ''
    echo "converting propagatedBuildOutputs to a space-separated string"
    export propagatedBuildOutputs="''${propagatedBuildOutputs[@]}"
  '';

  # NOTE: mkDerivation's setup.sh clobbers all dependency files in fixupPhase, so we must register the paths in postFixup.
  postFixup =
    # The `out` output should largely be empty save for nix-support/propagated-build-inputs.
    # In effect, this allows us to make `out` depend on all the other components.
    ''
      mkdir -p "$out/nix-support"
    ''
    # NOTE: We must use printWords to ensure the output is a single line.
    # See addPkg in ./pkgs/build-support/buildenv/builder.pl -- it splits on spaces.
    # TODO: The comment in the for-loop says to skip out and dev, but the code only skips out.
    # Since `dev` depends on `out` by default, wouldn't this cause a cycle?
    + ''
      for output in $(getAllOutputNames); do
        # Skip out and dev outputs
        [[ ''${output:?} == "out" || ''${output:?} == "dev" ]] && continue
        # Propagate the other components to the out output
        echo "adding output ''${output:?} to output out's propagated-build-inputs"
        printWords "''${!output:?}" >> "$out/nix-support/propagated-build-inputs"
      done
      unset -v output
    '';

  passthru = {
    debBuilderArgs = {
      # aarch64-linux, etc.
      targetStringDouble = "${parsed.cpu.name}-${parsed.kernel.name}";

      # aarch64-linux-gnu, etc.
      targetStringTriple = "${debBuilderArgs.targetStringDouble}-${parsed.abi.name}";
    };

    # Order is important here so we use a list.
    expectedOutputs = [
      "out"
      "doc"
      "sample"
      "python"
      "bin"
      "dev"
      "include"
      "lib"
      "static"
      "stubs"
    ];

    # Traversed in the order of the outputs speficied in outputs;
    # entries are skipped if they don't exist in outputs.
    outputToPatterns = {
      bin = [ "bin" ];
      dev = [
        "**/*.pc"
        "**/*.cmake"
      ];
      include = [ "include" ];
      lib = [
        "lib"
        "lib64"
      ];
      static = [ "**/*.a" ];
      sample = [ "samples" ];
      python = [ "**/*.whl" ];
      stubs = [
        "stubs"
        "lib/stubs"
      ];
    };

    # Useful for introspecting why something went wrong. Maps descriptions of why the derivation would be marked as
    # broken on have badPlatforms include the current platform.

    # brokenConditions :: AttrSet Bool
    # Sets `meta.broken = true` if any of the conditions are true.
    # Example: Broken on a specific version of CUDA or when a dependency has a specific version.
    # NOTE: Do not use this when a broken condition means evaluation will fail! For example, if
    # a package is missing and is required for the build -- that should go in badPlatformsConditions,
    # because attempts to access attributes on the package will cause evaluation errors.
    brokenConditions = {
      # Typically this results in the static output being empty, as all libraries are moved
      # back to the lib output.
      "lib output follows static output" =
        let
          libIndex = findFirstIndex (x: x == "lib") null finalAttrs.outputs;
          staticIndex = findFirstIndex (x: x == "static") null finalAttrs.outputs;
        in
        libIndex != null && staticIndex != null && libIndex > staticIndex;
      "Non Jetson builds are unsupported" = !flags.isJetsonBuild;
    };

    # badPlatformsConditions :: AttrSet Bool
    # Sets `meta.badPlatforms = meta.platforms` if any of the conditions are true.
    # Example: Broken on a specific architecture when some condition is met, like targeting Jetson or
    # a required package missing.
    # NOTE: Use this when a broken condition means evaluation can fail!
    badPlatformsConditions = {
      "Platform is not supported" = hostRedistSystem == "unsupported";
    };
  };

  meta = {
    description = "${debBuilderArgs.releaseInfo.name}. By downloading and using the packages you accept the terms and conditions of the ${finalAttrs.meta.license.shortName}";
    sourceProvenance = [ sourceTypes.binaryNativeCode ];
    broken =
      warnIfNot config.cudaSupport
        "CUDA support is disabled and you are building a CUDA package (${finalAttrs.finalPackage.name}); expect breakage!"
        (hasAnyTrueValue finalAttrs.passthru.brokenConditions);
    platforms = [ "aarch64-linux" ];
    badPlatforms = optionals (hasAnyTrueValue finalAttrs.passthru.badPlatformsConditions) (unique [
      stdenv.buildPlatform.system
      stdenv.hostPlatform.system
      stdenv.targetPlatform.system
    ]);
    license = licenses.unfree;
  };
}
