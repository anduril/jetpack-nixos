{ buildFromDebs
, cudaDriverMajorMinorVersion
, debs
, lib
, libgcc
, xorg
}:
let
  findDriverDebNames = majorVersion: lib.filter (lib.hasSuffix "-${majorVersion}") (lib.attrNames debs.common);
  driverDebNames = findDriverDebNames (lib.versions.major cudaDriverMajorMinorVersion);
  driverDebs = lib.genAttrs driverDebNames (pname: buildFromDebs {
    inherit pname;
    repo = "common";

    buildInputs = lib.attrByPath [ pname ] [ ] {
      libnvidia-compute-580 = [ driverDebs.libnvidia-decode-580 libgcc ];
      libnvidia-decode-580 = [ xorg.libX11 xorg.libXext ];
      libnvidia-encode-580 = [ driverDebs.libnvidia-decode-580 ];
      libnvidia-fbc1-580 = [ xorg.libX11 xorg.libXext ];
      libnvidia-gl-580 = [ xorg.libX11 xorg.libXext libgcc driverDebs.libnvidia-gpucomp-580 ];
    };
  });
in
driverDebs
