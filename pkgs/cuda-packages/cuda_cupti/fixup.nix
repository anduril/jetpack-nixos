# NOTE: All fixups must be at least binary functions to avoid callPackage adding override attributes.
_: prevAttrs: {
  allowFHSReferences = true;
  debNormalization =
    prevAttrs.debNormalization or ""
    + ''
      pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null
      mv \
        --verbose \
        --no-clobber \
        --target-directory "$PWD" \
        "$PWD/extras/CUPTI/samples"
      echo "removing $PWD/extras"
      rm --recursive --dir "$PWD/extras" || {
        nixErrorLog "$PWD/extras contains non-empty directories: $(ls -laR "$PWD/extras")"
        exit 1
      }
      popd >/dev/null
    '';
}
