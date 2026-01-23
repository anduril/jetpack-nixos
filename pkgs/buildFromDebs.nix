{ autoAddDriverRunpath
, autoPatchelfHook
, config
, cudaPackages
, debs
, dpkg
, lib
, stdenv
, defaultSomDebRepo
}:

{ pname
, repo ? defaultSomDebRepo
, version ? debs.${repo}.${pname}.version
, srcs ? [ debs.${repo}.${pname}.src ]
, sourceRoot ? "source"
, buildInputs ? [ ]
, nativeBuildInputs ? [ ]
, autoPatchelf ? true
, preDebNormalization ? ""
, postDebNormalization ? ""
, postPatch ? ""
, postFixup ? ""
, ...
}@args:

# NOTE: Using @args with specified values and ... binds the values in ... to args.
stdenv.mkDerivation (finalAttrs: removeAttrs args [ "autoPatchelf" "preDebNormalization" "postDebNormalization" "srcs" ] // {
  inherit pname version postPatch sourceRoot;

  nativeBuildInputs =
    [ dpkg ]
      # autoPatchelfHook must run before autoAddDriverRunpath
      ++ lib.optionals autoPatchelf [ autoPatchelfHook ]
      ++ lib.optionals config.cudaSupport [ cudaPackages.markForCudatoolkitRootHook autoAddDriverRunpath ]
      ++ nativeBuildInputs;
  buildInputs = [ stdenv.cc.cc.lib ] ++ buildInputs;

  # NOTE: The derivation expects sourceRoot to be "source", so we need to make sure to set the name attribute on the
  # normalized, unpacked debians.
  src = (cudaPackages.normalizeDebs {
    inherit srcs;
    inherit (finalAttrs) version;
    pname = finalAttrs.pname + "-" + "debs";
    inherit preDebNormalization postDebNormalization;
  }).overrideAttrs { name = "source"; };

  dontConfigure = true;
  dontBuild = true;
  noDumpEnvVars = true;

  installPhase = ''
    runHook preInstall

    cp -r . $out

    runHook postInstall
  '';

  # In cross-compile scenarios, the directory containing `libgcc_s.so` and other such
  # libraries is actually under a target-specific directory such as
  # `${stdenv.cc.cc.lib}/aarch64-unknown-linux-gnu/lib/` rather than just plain `/lib` which
  # makes `autoPatchelfHook` fail at finding them libraries.
  postFixup = lib.optionalString (autoPatchelf && stdenv.hostPlatform != stdenv.buildPlatform) ''
    addAutoPatchelfSearchPath ${stdenv.cc.cc.lib}/*/lib/
  '' + ''
    ${postFixup}
  '';

  meta = {
    platforms = [ "aarch64-linux" ];
  } // (args.meta or { });
})
