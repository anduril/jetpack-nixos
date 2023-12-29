{ lib
, runCommand
, dpkg
, debs
}:

runCommand "container-deps" { nativeBuildInputs = [ dpkg ]; }
  (lib.concatStringsSep "\n"
    (lib.mapAttrsToList
      (deb: debFiles:
      (if builtins.hasAttr deb debs.t234 then ''
        echo Unpacking ${deb}; dpkg -x ${debs.t234.${deb}.src} debs
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
      (lib.importJSON ./l4t.json)))
