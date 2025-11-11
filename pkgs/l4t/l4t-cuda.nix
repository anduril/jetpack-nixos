{ buildFromDebs
, cudaDriverMajorMinorVersion
, debs
, defaultSomDebRepo
, l4t-core
, l4tMajorMinorPatchVersion
, lib
,
}:
buildFromDebs {
  pname = "nvidia-l4t-cuda";
  buildInputs = [ l4t-core ];

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
