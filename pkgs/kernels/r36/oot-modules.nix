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

  l4t-oot-projects = {
    hwpm = gitRepos.hwpm;
    nvidia-oot = applyPatches {
      name = "nvidia-oot";
      src = gitRepos.nvidia-oot;
      patches = [
        ./patches/nvidia-oot/0001-rtl8822ce-Fix-Werror-address.patch
        ./patches/nvidia-oot/0002-sound-Fix-include-path-for-tegra-virt-alt-include.patch
        ./patches/nvidia-oot/0003-Fix-conftest-use-with-gcc15.patch
      ];
    };
    nvgpu = gitRepos.nvgpu;
    nvdisplay = applyPatches {
      name = "nvdisplay";
      src = gitRepos.nvdisplay;
      patches = [
        ./patches/nvdisplay/0001-nvidia-drm-Guard-nv_dev-in-nv_drm_suspend_resume.patch
        ./patches/nvdisplay/0002-ANDURIL-Add-some-missing-BASE_CFLAGS.patch
        ./patches/nvdisplay/0003-ANDURIL-Update-drm_gem_object_vmap_has_map_arg-test.patch
        ./patches/nvdisplay/0004-ANDURIL-override-KERNEL_SOURCES-and-KERNEL_OUTPUT-if.patch
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
      ''
      # copy the projects
      + (lib.strings.concatStringsSep "\n" (lib.mapAttrsToList
        (name: project: ''
          mkdir -p "$out/${name}"
          cp --no-preserve=all -vr "${project}"/. "$out/${name}"
        '')
        l4t-oot-projects))
      # See bspSrc/source/source_sync.sh symlink at end of file
      + ''
        ln -vsrf "$out/nvethernetrm" "$out/nvidia-oot/drivers/net/ethernet/nvidia/nvethernet/nvethernetrm"
      ''
    );
in
stdenv.mkDerivation {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "l4t-oot-modules";
  version = "${l4tMajorMinorPatchVersion}";
  src = l4t-oot-modules-sources;

  nativeBuildInputs = kernel.moduleBuildDependencies;
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  # See bspSrc/source/Makefile
  # We can't use kernelModuleMakeFlags because it sets KBUILD_OUTPUT, which nvdisplay won't like. DON'T DO IT!
  makeFlags = kernel.commonMakeFlags ++ [
    "KERNEL_HEADERS=${kernel.dev}/lib/modules/${kernel.modDirVersion}/source"
    "KERNEL_OUTPUT=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "INSTALL_MOD_PATH=$(out)"
    "IGNORE_PREEMPT_RT_PRESENCE=1"
  ];

  postInstall = ''
    mkdir -p $dev
    cat **/Module.symvers > $dev/Module.symvers

    mkdir -p $dev/include/nvidia
    cp -r out/nvidia-conftest/nvidia/* $dev/include/nvidia/
  '';

  outputs = [
    "out"
    "dev"
  ];

  # # GCC 14.2 seems confused about DRM_MODESET_LOCK_ALL_BEGIN/DRM_MODESET_LOCK_ALL_END in nvdisplay/kernel-open/nvidia-drm/nvidia-drm-drv.c:1344
  # extraMakeFlags = [ "KCFLAGS=-Wno-error=unused-label" ];

  buildFlags = [ "modules" ];
  installTargets = [ "modules_install" ];
}
