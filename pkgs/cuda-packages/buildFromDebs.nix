{ stdenv, debs, lib, dpkg, autoPatchelfHook, autoAddDriverRunpath, cudaVersion }:

{ pname
, srcs
, version ? debs.common.${pname}.version
, sourceRoot ? "source"
, buildInputs ? [ ]
, nativeBuildInputs ? [ ]
, postPatch ? ""
, postFixup ? ""
, ...
}@args:
# NOTE: Using @args with specified values and ... binds the values in ... to args.
stdenv.mkDerivation (args // {
  inherit pname version srcs sourceRoot;

  nativeBuildInputs = [ dpkg autoPatchelfHook autoAddDriverRunpath ] ++ nativeBuildInputs;
  buildInputs = [ stdenv.cc.cc.lib ] ++ buildInputs;

  unpackCmd = "for src in $srcs; do dpkg-deb -x $src source; done";

  dontConfigure = true;
  dontBuild = true;
  noDumpEnvVars = true;


  # In cross-compile scenarios, the directory containing `libgcc_s.so` and other such
  # libraries is actually under a target-specific directory such as
  # `${stdenv.cc.cc.lib}/aarch64-unknown-linux-gnu/lib/` rather than just plain `/lib` which
  # makes `autoPatchelfHook` fail at finding them libraries.
  postFixup = (lib.optionalString (stdenv.hostPlatform != stdenv.buildPlatform) ''
    addAutoPatchelfSearchPath ${stdenv.cc.cc.lib}/*/lib/
  '') + postFixup;

  postPatch = ''
    if [[ -d usr ]]; then
      cp -r usr/. .
      rm -rf usr
    fi

    if [[ -d local ]]; then
      cp -r local/. .
      rm -rf local
    fi

    if [[ -d cuda-${cudaVersion} ]]; then
      [[ -L cuda-${cudaVersion}/include ]] && rm -r cuda-${cudaVersion}/include
      [[ -L cuda-${cudaVersion}/lib64 ]] && rm -r cuda-${cudaVersion}/lib64 && ln -s lib lib64
      cp -r cuda-${cudaVersion}/. .
      rm -rf cuda-${cudaVersion}
    fi

    if [[ -d targets ]]; then
      cp -r targets/*/* .
      rm -rf targets
    fi

    if [[ -d etc ]]; then
      rm -rf etc/ld.so.conf.d
      rmdir --ignore-fail-on-non-empty etc
    fi

    if [[ -d include/aarch64-linux-gnu ]]; then
      cp -r include/aarch64-linux-gnu/. include/
      rm -rf include/aarch64-linux-gnu
    fi

    if [[ -d lib/aarch64-linux-gnu ]]; then
      cp -r lib/aarch64-linux-gnu/. lib/
      rm -rf lib/aarch64-linux-gnu
    fi

    if [[ -e "$PWD/lib64" ]]; then
      nixErrorLog "TODO(@connorbaker): $PWD/lib64's exists, copy everything into lib and make lib64 a symlink to lib"
      ls -la "$PWD/lib64"
      ls -laR "$PWD/lib64/"
      exit 1
    elif [[ -d "$PWD/lib" ]]; then
      if [[ -L "$PWD/lib64" ]]; then
        echo "removing existing symlink $PWD/lib64"
        rm "$PWD/lib64"
      fi
      if [[ -n "$(find "$PWD/lib" -not \( -path "$PWD/lib/stubs" -prune \) -name \*.so)" ]] ; then
        echo "symlinking $PWD/lib64 -> $PWD/lib"
        ln -rs "$PWD/lib" "$PWD/lib64"
      fi
    fi

    rm -f lib/ld.so.conf

    ${postPatch}
  '';

  installPhase = ''
    runHook preInstall

    cp -r . $out

    runHook postInstall
  '';

  meta = {
    platforms = [ "aarch64-linux" ];
  } // (args.meta or { });
})
