{ applyPatches
, bspSrc
, buildPackages
, gitRepos
, kernel
, l4tMajorMinorPatchVersion
, lib
, runCommand
, stdenv
, ...
}:
let
  patchedBsp = applyPatches {
    name = "patchedBsp";
    src = bspSrc;
    patches = [
      ./Makefile.diff
    ];
  };

  mkCopyProjectCommand = name: project: ''
    mkdir -p "$out/${name}"
    cp --no-preserve=all -vr "${project}"/. "$out/${name}"
  '';

  l4t-oot-projects = {
    inherit (gitRepos) hwpm nvgpu nvdisplay unifiedgpudisp;
    nvidia-oot = applyPatches {
      name = "nvidia-oot";
      src = gitRepos.nvidia-oot;
      patches = [
        ./0001-Fix-conftest-use-with-gcc15.patch
        ./0002-Fix-header-guard-in-halfrf_ops_rtl8852c.h.patch
      ];
    };
    nvethernetrm = applyPatches {
      name = "nvethernetrm";
      src = gitRepos.nvethernetrm;
      # Some directories in the git repo are RO.
      # This works for L4T b/c they use different output directory
      postPatch = ''
        chmod -R u+w osi
      '';
    };
  };

  l4t-oot-modules-sources = runCommand "l4t-oot-sources" { }
    (
      # Copy the Makefile
      ''
        mkdir -p "$out"
        cp "${patchedBsp}/source/Makefile" "$out/Makefile"
        cp "${patchedBsp}/source/kernel_src_build_env.sh" "$out/kernel_src_build_env.sh"
      ''
      # copy the projects
      + lib.strings.concatMapAttrsStringSep "\n" mkCopyProjectCommand l4t-oot-projects
      # See bspSrc/source/source_sync.sh symlink at end of file
      + ''
        ln -vsrf "$out/nvethernetrm" "$out/nvidia-oot/drivers/net/ethernet/nvidia/nvethernet/nvethernetrm"
      ''
    );
in
stdenv.mkDerivation (finalAttrs: {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "l4t-oot-modules";
  version = "${l4tMajorMinorPatchVersion}";
  src = l4t-oot-modules-sources;

  inherit kernel;

  nativeBuildInputs = finalAttrs.kernel.moduleBuildDependencies;
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  # See bspSrc/source/Makefile
  makeFlags = finalAttrs.kernel.makeFlags ++ [
    "KERNEL_HEADERS=${finalAttrs.kernel.dev}/lib/modules/${finalAttrs.kernel.modDirVersion}/source"
    "KERNEL_OUTPUT=${finalAttrs.kernel.dev}/lib/modules/${finalAttrs.kernel.modDirVersion}/build"
    "INSTALL_MOD_PATH=$(out)"
    # Maybe TODO: get these from kernel_src_build_env.sh directly
    "kernel_name=noble"
    "system_type=l4t"
  ];

  postInstall = ''
    mkdir -p $dev
    cat **/Module.symvers > $dev/Module.symvers

    mkdir -p $dev/include/nvidia
    install -m 0644 out/nvidia-conftest/nvidia/conftest.h $dev/include/nvidia/
  '';

  outputs = [
    "out"
    "dev"
  ];

  # # GCC 14.2 seems confused about DRM_MODESET_LOCK_ALL_BEGIN/DRM_MODESET_LOCK_ALL_END in nvdisplay/kernel-open/nvidia-drm/nvidia-drm-drv.c:1344
  # extraMakeFlags = [ "KCFLAGS=-Wno-error=unused-label" ];

  buildFlags = [ "modules" ];
  installTargets = [ "modules_install" ];
})
