{ lib
, runCommand
, dpkg
, debs
, l4tMajorMinorPatchVersion
, l4tAtLeast
}:

runCommand "container-deps" { nativeBuildInputs = [ dpkg ]; }
  (lib.concatStringsSep "\n"
    (lib.mapAttrsToList
      (deb: debFiles:
      let
        repo = if l4tAtLeast "38" then "som" else "t234";
      in
      (if builtins.hasAttr deb debs.${repo} then ''
        echo Unpacking ${deb}; dpkg -x ${debs.${repo}.${deb}.src} debs
      '' else ''
        echo Unpacking ${deb}; dpkg -x ${debs.common.${deb}.src} debs
      '') + (lib.concatStringsSep "\n" (map
        (file: ''
          if [[ -f debs${file} ]]; then
            install -D --target-directory=$out${builtins.dirOf file} debs${file}
          else
            echo "WARNING: file ${file} not found in deb ${deb}"
          fi
        '')
        debFiles)))
      (lib.importJSON ./r${lib.versions.majorMinor l4tMajorMinorPatchVersion}-l4t.json)))
