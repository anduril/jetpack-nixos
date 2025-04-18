# The Debian-archive builder largely wraps the redistributable builder.
{ callPackage
, cudaMajorMinorVersion
, debs
, debsForSourcePackage
, fetchurl
, lib
, stdenv
}:
let
  inherit (lib.attrsets) getAttr recursiveUpdate;
  inherit (lib.fixedPoints) composeManyExtensions toExtension;
  inherit (lib.lists)
    head
    length
    map
    unique
    ;
  inherit (lib.strings) removeSuffix replaceStrings;
  inherit (lib.trivial) pipe throwIf;

  mkOverrideAttrsFn = fixupFn: toExtension (callPackage fixupFn { });
  genericOverrideAttrsFn = mkOverrideAttrsFn ./fixup.nix;
in
{
  # Aggregate all the debs from the selected manifest with a `source` attribute matching this name.
  # NOTE: Not called `pname` since NVIDIA debians use a different naming scheme than their redist cousins.
  sourceName
, outputs
, releaseInfo
, # Fixup functions are callPackage'd and supplied to overrideAttrs
  fixupFns ? [ ]
, packageName ? (replaceStrings [ "-" ] [ "_" ] sourceName)
}:
let
  filteredDebs = debsForSourcePackage sourceName;
  debPkgs = map (getAttr "src") filteredDebs;
  defaultVersion =
    let
      uniqueVersions = unique (map (getAttr "version") filteredDebs);
      uniqueVersion = pipe uniqueVersions [
        head
        (removeSuffix "+cuda${cudaMajorMinorVersion}")
        (removeSuffix "-1")
      ];
    in
    throwIf (length uniqueVersions != 1)
      "deb-builder: expected a single version for ${sourceName}, found ${builtins.toJSON uniqueVersions}"
      uniqueVersion;

  extension = composeManyExtensions (
    [
      genericOverrideAttrsFn
      (_: prevAttrs: {
        passthru = recursiveUpdate (prevAttrs.passthru or { }) {
          debBuilderArgs = {
            inherit outputs packageName;
            debs = debPkgs;
            releaseInfo = releaseInfo // {
              version = releaseInfo.version or defaultVersion;
            };
          };
        };
      })
    ]
    ++ map (fixupFn: toExtension (callPackage fixupFn { })) fixupFns
  );
in
stdenv.mkDerivation (finalAttrs: extension finalAttrs { })
