{ stdenv
, lib
, buildPackages
}:

# For some unknown reason multiple Nvidia libraries hard code dlopen paths.
# For example the libnvscf.so library has a dlopen call to a hard path:
# `/usr/lib/aarch64-linux-gnu/tegra-egl/libEGL_nvidia.so.0`
# This causes loading errors for libargus applications and the nvargus-daemon.
# Errors will look like this:
# SCF: Error NotSupported: Failed to load EGL library
#
# To fix this, we are creating a dlopen shim that replaces the hard coded path with a known good path
#
# To use this pass rewrites which is an attribute set of the form
# { oldPath = newPath; }
# And a file which is just a string to the exact path of the lib
#
# Also, we have to clear the dlopen symbol version because when we rename the
# symbol it holds onto the original dlopen's symbol version (GLIBC_x.yy).
# This version likely does not match the GLIBC version used to compile
# dlopenoverride (stdenv.mkDerivation above)
rewrites: file:
let
  oldPaths = builtins.attrNames rewrites;
  newPaths = builtins.attrValues rewrites;
  dlopenUnique = "__dlopen${builtins.hashString "sha256" (builtins.toJSON rewrites)}";
  dlopen = stdenv.mkDerivation {
    pname = "dlopen-override";
    version = "1.0";

    strictDeps = true;

    src = ./.;

    patchPhase = ''
      substituteInPlace dlopenoverride.c \
          --replace-fail \
            '@oldpaths@' \
            '${ builtins.concatStringsSep "\",\"" oldPaths }' \
          --replace-fail \
            '@newpaths@' \
            '${ builtins.concatStringsSep "\",\"" newPaths }' \
          --replace-fail \
            '__dlopen' \
            '${dlopenUnique}'
    '';

    buildPhase = ''
      runHook preBuild

      $CC -shared -fPIC -o dlopen-override.so dlopenoverride.c -ldl

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 dlopen-override.so "$out"/lib/dlopen-override.so

      runHook postInstall
    '';
  };
in
''
  (
    remapFile=$(mktemp)
    echo dlopen ${dlopenUnique} > $remapFile
    ${lib.getExe buildPackages.patchelfUnstable} ${file} \
      --clear-symbol-version dlopen \
      --rename-dynamic-symbols "$remapFile" \
      --add-needed ${dlopen}/lib/dlopen-override.so \
      --add-rpath ${dlopen}/lib
    rm $remapFile
  )
''
