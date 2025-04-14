# NOTE: All fixups must be at least binary functions to avoid callPackage adding override attributes.
{ lib
, libcublas
, patchelf
, zlib
,
}:
let
  inherit (lib.attrsets) getLib;
  inherit (lib.meta) getExe;
in
prevAttrs: {
  buildInputs = prevAttrs.buildInputs or [ ] ++ [
    (getLib libcublas)
    zlib
  ];

  postFixup =
    prevAttrs.postFixup or ""
    + ''
      echo "patchelf-ing libcudnn with runtime dependencies"
      "${getExe patchelf}" "''${!outputLib:?}/lib/libcudnn.so" --add-needed libcudnn_cnn_infer.so
      "${getExe patchelf}" "''${!outputLib:?}/lib/libcudnn_ops_infer.so" --add-needed libcublas.so --add-needed libcublasLt.so

      echo "creating symlinks for header files in include without the _v8 suffix before the file extension"
      pushd "''${!outputInclude:?}/include" >/dev/null
      for file in *.h; do
        echo "symlinking $file to $(basename "$file" "_v8.h").h"
        ln -s "$file" "$(basename "$file" "_v8.h").h"
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
