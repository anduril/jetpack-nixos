{ buildFromDebs
, cudaDriverMajorMinorVersion
, debs
, defaultSomDebRepo
, l4tAtLeast
, l4t-core
, l4tMajorMinorPatchVersion
, lib
,
}:
buildFromDebs {
  pname = "nvidia-l4t-cuda";
  # l4t-cuda and l4t-cuda-openrm are interdependent; can't repack them separately
  srcs = [ debs.${defaultSomDebRepo}.nvidia-l4t-cuda.src ] ++ lib.optionals (l4tAtLeast "39") [ debs.${defaultSomDebRepo}.nvidia-l4t-cuda-openrm.src ];
  buildInputs = [ l4t-core ];

  postDebNormalization = lib.optionalString (l4tAtLeast "39") ''
    pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null

    nixLog "moving libs to top-level lib directory"
    mkdir -p $PWD/lib
    mv --verbose --no-clobber "$PWD/opt/nvidia/l4t-gpu-libs/openrm/"*.so* "$PWD/lib"

    popd >/dev/null
  '';

  postPatch =
    let
      version = lib.defaultTo l4tMajorMinorPatchVersion cudaDriverMajorMinorVersion;
      folder = if cudaDriverMajorMinorVersion == null then "tegra" else "nvidia";
    in
    ''
      # Additional libcuda symlinks
      ln -sf libcuda.so.1.1 lib/libcuda.so.1
      ln -sf libcuda.so.1.1 lib/libcuda.so

      # Also unpack l4t-3d-core so we can grab libnvidia-ptxjitcompiler from it
      # and include it in this library.
      #
      # It's unclear why NVIDIA has this library in l4t-3d-core and not in
      # l4t-core. Even more so since the cuda compat package has libcuda as
      # well as libnvidia-ptxjitcompiler in the same package. meta-tegra does a
      # similar thing where they pull libnvidia-ptxjitcompiler out of
      # l4t-3d-core and place it in the same package as libcuda.
      dpkg --fsys-tarfile ${debs.${defaultSomDebRepo}.nvidia-l4t-3d-core.src} | tar -xO ./usr/lib/aarch64-linux-gnu/${folder}/libnvidia-ptxjitcompiler.so.${version} > lib/libnvidia-ptxjitcompiler.so.${version}
      ln -sf libnvidia-ptxjitcompiler.so.${version} lib/libnvidia-ptxjitcompiler.so.1
      ln -sf libnvidia-ptxjitcompiler.so.${version} lib/libnvidia-ptxjitcompiler.so
    '';

  # libcuda.so actually depends on libnvcucompat.so at runtime (probably
  # through `dlopen`), so we need to tell Nix about this.
  postFixup = ''
    patchelf --add-needed libnvcucompat.so $out/lib/libcuda.so
  '';
}
