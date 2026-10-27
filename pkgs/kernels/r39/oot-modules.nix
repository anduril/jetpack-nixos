{ applyPatches
, bspSrc
, buildPackages
, gitRepos
, hypervisorGuestSupport ? false
, kernel
, kernelName ? "noble"
, l4tMajorMinorPatchVersion
, lib
, runCommand
, stdenv
, ...
}:
let
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
        ./0001-crypto-tegra-Disable-softirqs-before-finalizing-requ.patch
        ./0001-Lower-priority-of-tegra-se-crypto.patch
        # Some boards hit QSPI_DMA_TIMEOUT's flat 1s limit on large transfers.
        # Scale the timeout to the transfer's size and negotiated speed.
        ./0002-spi-tegra210-quad-scale-xfer-completion-timeout-to-.patch
      ]
      # Needs NV_OOT_TEGRA_HV_SKIP_BUILD=y, which both configs/Makefile.config.{noble,nvmainline} set.
      ++ lib.optional (!hypervisorGuestSupport) ./0001-Skip-hypervisor-guest-modules.patch
      # Mainline has no tegra_hv_ivc_* implementation; bare-metal modules (tegra-drm) still reference it.
      ++ lib.optional (kernelName == "nvmainline") ./0002-tegra_hv-dummy-export-bare-metal-IVC-stubs.patch;
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
        cp "${bspSrc}/source/Makefile" "$out/Makefile"
        cp "${bspSrc}/source/kernel_src_build_env.sh" "$out/kernel_src_build_env.sh"
      ''
      # copy the projects
      + lib.strings.concatMapAttrsStringSep "\n" mkCopyProjectCommand l4t-oot-projects
      # See bspSrc/source/source_sync.sh symlink at end of file
      + ''
        ln -vsrf "$out/nvethernetrm" "$out/nvidia-oot/drivers/net/ethernet/nvidia/nvethernet/nvethernetrm"
      ''
    );

  # nixpkgs' kernel.makeFlags contains `O=$(buildRoot)`, and buildRoot is unset
  # here. With kernel >= 7 an empty O= overrides the KBUILD_OUTPUT exported by
  # the dev output's build/Makefile, so kbuild looks for auto.conf in the
  # read-only source tree and fails.
  kernelMakeFlags =
    if kernelName == "nvmainline"
    then lib.filter (flag: !(lib.hasPrefix "O=" flag)) kernel.makeFlags
    else kernel.makeFlags;
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
  makeFlags = kernelMakeFlags ++ [
    "KERNEL_HEADERS=${finalAttrs.kernel.dev}/lib/modules/${finalAttrs.kernel.modDirVersion}/source"
    "KERNEL_OUTPUT=${finalAttrs.kernel.dev}/lib/modules/${finalAttrs.kernel.modDirVersion}/build"
    "INSTALL_MOD_PATH=$(out)"
    # Maybe TODO: get these from kernel_src_build_env.sh directly
    "kernel_name=${kernelName}"
    "system_type=l4t"
  ]
    # configs/Makefile.config.nvmainline assumes NVIDIA's kernel, which already has the IVC
    # extensions (tegra_ivc_can_read/read/write/...) that the camera RTCPU, etc. use. Vanilla
    # mainline does not, so build nvidia-oot's own ivc_ext instead of the dummy.
    ++ lib.optionals (kernelName == "nvmainline") [
    "NV_OOT_IVC_EXT_SKIP_BUILD=n"
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
})
