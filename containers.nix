{
  lib,
  stdenv,
  dpkg,
  debs,
  fetchFromGitHub,
  libelf,
  libcap,
  libtirpc,
  libseccomp,
  substituteAll,
  bspSrc,
  pkgs,
  pkg-config,
  rpcsvc-proto,
}:


let
  # First, extract the l4t.xml from the root image to know what packages are expected to be present.
  l4tCsv = pkgs.runCommand "l4t.csv" {} ''
    tar -xf "${bspSrc}/nv_tegra/config.tbz2"
    mkdir -p "$out"
    mv etc/nvidia-container-runtime/host-files-for-container.d/l4t.csv "$out"
  '';

  # make a single sources root of all the debs.
  # given this is WAY more stuff than we need, we should be able to dramatically reduce this by intersecting at extract time with l4t.csv.
  # However, this was beyond my bash skills at time of writing and I can't spare more time on this.
  # In theory, we could also filter the list of debs that have been extracted - however this will be less efficient.
  unpackedDebs = pkgs.runCommand "depsForContainer" { nativeBuildInputs = [ dpkg ]; } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out") debs.common)}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out") debs.t234)}
  '';

  modprobeVersion = "396.51";
  nvidia-modprobe = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "nvidia-modprobe";
    rev = modprobeVersion;
    sha256 = "sha256-c2G0qatv0LMZ0RAbluB9TyHkZAVbdGf4U8RMghjHgrs=";
  };
  modprobePatch = substituteAll {
    src = ./modprobe.patch;
    inherit modprobeVersion;
  };

  libnvidia_container0 = stdenv.mkDerivation rec {
    pname = "libnvidia-container";
    version = "0.11.0+jetpack";
    src = fetchFromGitHub {
      owner = "NVIDIA";
      repo = "libnvidia-container";
      rev = "v${version}";
      sha256 = "sha256-dRK0mmewNL2jIvnlk0YgCfTHuIc3BuZhIlXG5VqBQ5Q=";
    };
    patches = [
      ./nvc-ldcache.patch
      ./avoid-static-libtirpc-build.patch
      ./libcontainer-nixos-base.patch
    ];
    postPatch = ''
      sed -i \
        -e 's/^REVISION :=.*/REVISION = ${src.rev}/' \
        -e 's/^COMPILER :=.*/COMPILER = $(CC)/' \
        mk/common.mk

      sed -i 's#/etc/nvidia-container-runtime/host-files-for-container.d#${l4tCsv}#' src/nvc_info.c
      sed -i 's#NIXOS_ROOT#${unpackedDebs}#' src/common.h

      mkdir -p deps/src/nvidia-modprobe-${modprobeVersion}
      cp -r ${nvidia-modprobe}/* deps/src/nvidia-modprobe-${modprobeVersion}
      chmod -R u+w deps/src
      pushd deps/src

      # patch -p0 < ${modprobePatch}
      touch nvidia-modprobe-${modprobeVersion}/.download_stamp
      popd

      # 1. replace DESTDIR=$(DEPS_DIR) with empty strings to prevent copying
      #    things into deps/src/nix/store
      # 2. similarly, remove any paths prefixed with DEPS_DIR
      # 3. prevent building static libraries because we don't build static
      #    libtirpc (for now)
      # 4. prevent installation of static libraries because of step 3
      # 5. prevent installation of libnvidia-container-go.so twice
      sed -i Makefile \
        -e 's#DESTDIR=\$(DEPS_DIR)#DESTDIR=""#g' \
        -e 's#\$(DEPS_DIR)\$#\$#g' \
        -e 's#all: shared static tools#all: shared tools#g' \
        -e '/$(INSTALL) -m 644 $(LIB_STATIC) $(DESTDIR)$(libdir)/d' \
        -e '/$(INSTALL) -m 755 $(libdir)\/$(LIBGO_SHARED) $(DESTDIR)$(libdir)/d'
    '';

    enableParallelBuilding = true;

    preBuild = ''
      HOME="$(mktemp -d)"
    '';

    NIX_CFLAGS_COMPILE = toString [ "-I${libtirpc.dev}/include/tirpc" ];
    NIX_LDFLAGS = [ "-L${libtirpc}/lib" "-ltirpc" ];

    nativeBuildInputs = [ pkg-config rpcsvc-proto ];

    buildInputs = [ libelf libcap libseccomp libtirpc ];

    makeFlags = [
      "WITH_LIBELF=yes"
      "prefix=$(out)"
      # we can't use the WITH_TIRPC=yes flag that exists in the Makefile for the
      # same reason we patch out the static library use of libtirpc so we set the
      # define in CFLAGS
      "CFLAGS=-DWITH_TIRPC"
    ];
  };
in {
    inherit libnvidia_container0;
}