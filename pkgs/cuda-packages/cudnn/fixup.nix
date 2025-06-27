# NOTE: All fixups must be at least binary functions to avoid callPackage adding override attributes.
{ lib
, libcublas
, patchelf
, zlib
, cudaMajorVersion
,
}:
let
  inherit (lib.attrsets) getLib;
  inherit (lib.meta) getExe;

  cudnnMajorVersion = {
    "11" = "8";
    "12" = "9";
  }.${cudaMajorVersion};
in
prevAttrs: {
  buildInputs = prevAttrs.buildInputs or [ ] ++ [
    (getLib libcublas)
    zlib
  ];

  postFixup =
    prevAttrs.postFixup or ""
    + lib.optionalString (lib.versionAtLeast cudnnMajorVersion "9") ''
      pushd "''${!outputLib:?}/lib" >/dev/null
      ln -s libcudnn.so.${cudnnMajorVersion} libcudnn.so
      popd >/dev/null
    ''
    + lib.optionalString (lib.versionOlder cudnnMajorVersion "9") ''
      echo "patchelf-ing libcudnn with runtime dependencies"
      "${getExe patchelf}" "''${!outputLib:?}/lib/libcudnn.so" --add-needed libcudnn_cnn_infer.so
      "${getExe patchelf}" "''${!outputLib:?}/lib/libcudnn_ops_infer.so" --add-needed libcublas.so --add-needed libcublasLt.so
    ''
    + ''
      echo "creating symlinks for header files in include without the _v${cudnnMajorVersion} suffix before the file extension"
      pushd "''${!outputInclude:?}/include" >/dev/null
      for file in *.h; do
        echo "symlinking $file to $(basename "$file" "_v${cudnnMajorVersion}.h").h"
        ln -s "$file" "$(basename "$file" "_v${cudnnMajorVersion}.h").h"
      done
      unset -v file
      popd >/dev/null
    '';

  meta = prevAttrs.meta or { } // {
    homepage = "https://developer.nvidia.com/cudnn";
    license = {
      shortName = "cuDNN EULA";
      fullName = "NVIDIA cuDNN Software License Agreement (EULA)";
      url = "https://docs.nvidia.com/deeplearning/sdk/cudnn-sla/index.html#supplement";
      free = false;
      redistributable = true;
    };
  };
}
