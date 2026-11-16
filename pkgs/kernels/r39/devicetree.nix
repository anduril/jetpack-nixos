{ bspSrc
, gitRepos
, kernel
, l4tMajorMinorPatchVersion
, lib
, mainline ? false
, runCommand
, stdenv
, buildPackages
, ...
}:
let
  l4t-devicetree-sources = runCommand "l4t-devicetree-sources" { }
    (lib.strings.concatStrings
      ([ "mkdir -p $out ; cp ${bspSrc}/source/Makefile $out/Makefile ;" ] ++
        lib.lists.forEach
          [ "hardware/nvidia/t264/nv-public" "hardware/nvidia/t23x/nv-public" "hardware/nvidia/tegra/nv-public" "build/nvidia-public" ]
          (
            project:
            ''
              mkdir -p "$out/${project}"
              cp --no-preserve=all -vr "${lib.attrsets.attrByPath [project] 0 gitRepos}"/. "$out/${project}"
            ''
          )));
in
stdenv.mkDerivation (finalAttrs: {
  pname = "l4t-devicetree";
  version = "${l4tMajorMinorPatchVersion}";
  src = l4t-devicetree-sources;
  __structuredAttrs = true;
  strictDeps = true;

  inherit kernel;

  nativeBuildInputs = finalAttrs.kernel.moduleBuildDependencies;
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  # See bspSrc/source/Makefile
  makeFlags = [
    "KERNEL_HEADERS=${finalAttrs.kernel.dev}/lib/modules/${finalAttrs.kernel.modDirVersion}/source"
    "KERNEL_OUTPUT=${finalAttrs.kernel.dev}/lib/modules/${finalAttrs.kernel.modDirVersion}/build"
  ];

  buildFlags = "dtbs";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"/
    # See build/nvidia-public/devicetree/Makefile.generic
    # The dtbs are installed to build/nvidia-public/devicetree/generic-dtbs
    install -Dm644 build/nvidia-public/devicetree/generic-dtbs/* "$out/"

    runHook postInstall
  '';
} // lib.optionalAttrs mainline {
  # BSP prod-settings contain register tuning, not I2C client devices.
  # Mainline ignores the data, but bus enumeration reports missing modaliases.
  # Disable only these I2C children in installed DTBs, retaining their data.
  postInstall = ''
    for dtb in "$out/"*.dtb; do
      for node in $(${lib.getExe' buildPackages.dtc "fdtget"} -l "$dtb" /bus@0); do
        if [[ "$node" == i2c@* ]] &&
          ${lib.getExe' buildPackages.dtc "fdtget"} -l "$dtb" "/bus@0/$node" | grep -Fxq prod-settings; then
          ${lib.getExe' buildPackages.dtc "fdtput"} -t s "$dtb" "/bus@0/$node/prod-settings" status disabled
        fi
      done
    done
  '';
})
