{ stdenv
, lib
, buildPackages
}:

# rewrites is an attribute set of the form
# { oldPath = newPath; }
rewrites: file:
let
  oldPaths = builtins.attrNames rewrites;
  newPaths = builtins.attrValues rewrites;
  dlopenUnique = "__dlopen${builtins.hashString "sha256" (builtins.toJSON rewrites)}";
  dlopen = stdenv.mkDerivation {
    pname = "dlopen-override";
    version = "1.0";

    strictDeps = true;

    src = ./dlopen-override;

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

      cc -shared -fPIC -o dlopen-override.so dlopenoverride.c -ldl

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
  remapFile=$(mktemp)
  echo dlopen ${dlopenUnique} > $remapFile
  ${lib.getExe buildPackages.patchelfUnstable} ${file} \
    --rename-dynamic-symbols "$remapFile" \
    --add-needed ${dlopen}/lib/dlopen-override.so \
    --add-rpath ${dlopen}/lib
''
