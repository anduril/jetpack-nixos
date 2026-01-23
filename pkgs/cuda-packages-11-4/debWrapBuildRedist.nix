{ cudaMajorMinorVersion
, lib
, normalizeDebs
, nvidia-jetpack
}:
let
  inherit (lib)
    composeExtensions
    getAttr
    head
    length
    map
    pipe
    removeSuffix
    replaceStrings
    throwIf
    toExtension
    unique
    ;
in
# `buildRedist` is close to what we need, but not exactly there.
  # `fromDeb` overrides parts of `buildRedist` to inject debian unpacking and normalization.
lib.makeOverridable (
  { drv
  , preDebNormalization ? ""
  , postDebNormalization ? ""
  , sourceName ? replaceStrings [ "_" ] [ "-" ] drv.pname
  , extension ? (_: _: { })
  }:
  let
    filteredDebs = nvidia-jetpack.debsForSourcePackage sourceName;
    fixup = finalAttrs: prevAttrs: {
      # They've basically all got FHS references through copyright notices or documentation.
      allowFHSReferences = true;

      version =
        let
          uniqueVersions = unique (map (getAttr "version") filteredDebs);
          uniqueVersion = pipe uniqueVersions [
            head
            (removeSuffix "+cuda${cudaMajorMinorVersion}")
            (removeSuffix "-1")
          ];
        in
        throwIf (length uniqueVersions != 1)
          "wrapBuildRedist: expected a single version for ${sourceName}, found ${builtins.toJSON uniqueVersions}"
          uniqueVersion;

      src = normalizeDebs {
        srcs = map (getAttr "src") filteredDebs;
        inherit (finalAttrs) version;
        pname = finalAttrs.pname + "-" + "debs";
        inherit preDebNormalization postDebNormalization;
      };

      passthru = prevAttrs.passthru // {
        # Doesn't come from a release manifest.
        release = null;
        # Only Jetson devices (pre-Thor) are supported.
        supportedNixSystems = [ "aarch64-linux" ];
        supportedRedistSystems = [ "linux-aarch64" ];
      };
    };
  in
  drv.overrideAttrs (composeExtensions fixup (toExtension extension))
)
