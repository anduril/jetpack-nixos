{ bspSrc
, l4tMajorMinorPatchVersion
, lib
, stdenvNoCC
,
}:
stdenvNoCC.mkDerivation {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "l4t-csv";
  version = l4tMajorMinorPatchVersion;

  src = "${bspSrc}/nv_tegra/config.tbz2";

  sourceRoot = "etc/nvidia-container-runtime/host-files-for-container.d";

  # We keep track of the file names so we can use them in the module system to enable nvidia-container-toolkit.
  # Also allows us to make sure we're copying over everything we should.
  fileNames =
    let
      l4tMajorVersion = lib.versions.major l4tMajorMinorPatchVersion;
    in
    if l4tMajorVersion == "35" then
      [ "l4t.csv" ]
    else if l4tMajorVersion == "36" then
      [
        "devices.csv"
        "drivers.csv"
      ]
    else if l4tMajorVersion == "38" then
      [
        "devices.csv"
        "drivers.csv"
      ]
    else
      builtins.throw "unhandled L4T version ${l4tMajorMinorPatchVersion}";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    for fileName in "''${fileNames[@]}"; do
      if [[ ! -e $fileName ]]; then
        nixErrorLog "file $fileName does not exist"
        exit 1
      fi
      mv -v "$fileName" "$out/"
    done

    runHook postInstall
  '';

  doInstallCheck = true;

  installCheckPhase = ''
    runHook preInstallCheck

    if [[ -n "$(ls -A)" ]]; then
      nixErrorLog "encountered unexpected files: $(ls -A)"
      exit 1
    fi
    nixLog "all CSV files are accounted for"

    runHook postInstallCheck
  '';
}
