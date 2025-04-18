# NOTE: All fixups must be at least binary functions to avoid callPackage adding override attributes.
{ addDriverRunpath
, cuda_nvcc
, flags
}:
prevAttrs: {
  # Include the static libraries as well since CMake needs them during the configure phase.
  propagatedBuildOutputs = prevAttrs.propagatedBuildOutputs or [ ] ++ [ "static" ];

  postPatch =
    prevAttrs.postPatch or ""
    # Patch the `cudart` package config files so they reference lib
    + ''
      while IFS= read -r -d $'\0' path; do
        echo "patching $path"
        sed -i \
          -e "s|^cudaroot\s*=.*\$||" \
          -e "s|^libdir\s*=.*/lib\$|libdir=''${!outputLib:?}/lib|" \
          -e "s|^includedir\s*=.*/include\$|includedir=''${!outputInclude:?}/include|" \
          -e "s|^Libs\s*:\(.*\)\$|Libs: \1 -Wl,-rpath,${addDriverRunpath.driverLink}/lib|" \
          "$path"
      done < <(find -iname 'cudart-*.pc' -print0)
    ''
    # Patch the `cuda` package config files so they reference stubs
    + ''
      while IFS= read -r -d $'\0' path; do
        echo "patching $path"
        sed -i \
          -e "s|^cudaroot\s*=.*\$||" \
          -e "s|^libdir\s*=.*/lib\$|libdir=''${!outputStubs:?}/lib/stubs|" \
          -e "s|^includedir\s*=.*/include\$|includedir=''${!outputInclude:?}/include|" \
          -e "s|^Libs\s*:\(.*\)\$|Libs: \1 -Wl,-rpath,${addDriverRunpath.driverLink}/lib|" \
          "$path"
      done < <(find -iname 'cuda-*.pc' -print0)
    '';

  postInstall =
    prevAttrs.postInstall or ""
    # NOTE: We can't patch a single output with overrideAttrs, so we need to use nix-support.
    + ''
      mkdir -p "''${!outputInclude:?}/nix-support"
    ''
    # Namelink may not be enough, add a soname.
    # Cf. https://gitlab.kitware.com/cmake/cmake/-/issues/25536
    + ''
      pushd "''${!outputStubs:?}/lib/stubs" >/dev/null
      if [[ -f libcuda.so && ! -f libcuda.so.1 ]]; then
        echo "creating versioned symlink for libcuda.so stub"
        ln -sr libcuda.so libcuda.so.1
      fi
      popd >/dev/null
    '';
}
