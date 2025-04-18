# NOTE: All fixups must be at least binary functions to avoid callPackage adding override attributes.
{ lib
, cuda_cudart
, cuda_nvrtc
, cudnn
, flags
, libcublas
, libcudla
, patchelf
}:
prevAttrs: {
  # Samples, lib, and static all reference a FHS
  allowFHSReferences = true;

  nativeBuildInputs = prevAttrs.nativeBuildInputs or [ ] ++ [ patchelf ];

  buildInputs = prevAttrs.buildInputs or [ ] ++ lib.map lib.getLib [
    cuda_cudart
    cuda_nvrtc
    cudnn
    libcublas
    libcudla
  ];

  debNormalization =
    prevAttrs.debNormalization or ""
    + ''
      pushd "$NIX_BUILD_TOP/$sourceRoot" >/dev/null
      mv --verbose --no-clobber "$PWD/src/tensorrt" "$PWD/samples"
      echo "removing $PWD/src"
      rm --recursive --dir "$PWD/src" || {
        nixErrorLog "$PWD/src contains non-empty directories: $(ls -laR "$PWD/extras")"
        exit 1
      }
      popd >/dev/null
    '';

  postFixup =
    prevAttrs.postFixup or ""
    + ''
      echo "patchelf-ing ''${!outputLib:?}/lib/libnvinfer.so with runtime dependencies"
      patchelf \
        "''${!outputLib:?}/lib/libnvinfer.so" \
        --add-needed libnvrtc.so \
        --add-needed libnvrtc-builtins.so
    '';

  passthru = prevAttrs.passthru or { } // {
    inherit cudnn;
  };
  meta = prevAttrs.meta or { } // {
    platforms = [ "aarch64-linux" ];
  };
}
