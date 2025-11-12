{ autoAddDriverRunpath
, autoPatchelfHook
, config
, cudaMajorMinorVersion
, cudaPackages
, debs
, dpkg
, lib
, stdenv
, defaultSomDebRepo
}:
let
in

{ pname
, repo ? defaultSomDebRepo
, version ? debs.${repo}.${pname}.version
, srcs ? [ debs.${repo}.${pname}.src ]
, sourceRoot ? "source"
, buildInputs ? [ ]
, nativeBuildInputs ? [ ]
, autoPatchelf ? true
, postPatch ? ""
, postFixup ? ""
, ...
}@args:
# NOTE: Using @args with specified values and ... binds the values in ... to args.
stdenv.mkDerivation ((lib.filterAttrs (n: v: !(builtins.elem n [ "autoPatchelf" ])) args) // {
  inherit pname version srcs sourceRoot;

  nativeBuildInputs =
    [ dpkg ]
      # autoPatchelfHook must run before autoAddDriverRunpath
      ++ lib.optionals autoPatchelf [ autoPatchelfHook ]
      ++ lib.optionals config.cudaSupport [ cudaPackages.markForCudatoolkitRootHook autoAddDriverRunpath ]
      ++ nativeBuildInputs;
  buildInputs = [ stdenv.cc.cc.lib ] ++ buildInputs;

  unpackCmd = "for src in $srcs; do dpkg-deb -x $src source; done";

  dontConfigure = true;
  dontBuild = true;
  noDumpEnvVars = true;


  # In cross-compile scenarios, the directory containing `libgcc_s.so` and other such
  # libraries is actually under a target-specific directory such as
  # `${stdenv.cc.cc.lib}/aarch64-unknown-linux-gnu/lib/` rather than just plain `/lib` which
  # makes `autoPatchelfHook` fail at finding them libraries.
  postFixup = (lib.optionalString (autoPatchelf && (stdenv.hostPlatform != stdenv.buildPlatform)) ''
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

    if [[ -d cuda-${cudaMajorMinorVersion} ]]; then
      [[ -L cuda-${cudaMajorMinorVersion}/include ]] && rm -r cuda-${cudaMajorMinorVersion}/include
      [[ -L cuda-${cudaMajorMinorVersion}/lib64 ]] && rm -r cuda-${cudaMajorMinorVersion}/lib64 && ln -s lib lib64
      cp -r cuda-${cudaMajorMinorVersion}/. .
      rm -rf cuda-${cudaMajorMinorVersion}
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

    if [[ -d lib/tegra ]]; then
      if [[ -n "$(ls lib/tegra)" ]] ; then
        mv -v -t lib lib/tegra/*
      fi
      rm -rf lib/tegra
    fi

    if [[ -d lib/nvidia ]]; then
      if [[ -n "$(ls lib/nvidia)" ]] ; then
        mv -v -t lib lib/nvidia/*
      fi
      rm -rf lib/nvidia
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
