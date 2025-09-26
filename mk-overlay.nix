# TODO(jared): Get rid of usage of `callPackages` where possible so we can take
# advantage of scope's `self.callPackage` (callPackages does not exist under
# `self`).

{ jetpackMajorMinorPatchVersion
, l4tMajorMinorPatchVersion
, cudaMajorMinorPatchVersion
, cudaDriverMajorMinorVersion
, bspHash
}:
final: _:
let
  inherit (final.lib)
    attrValues
    callPackageWith
    callPackagesWith
    composeManyExtensions
    concatMapAttrsStringSep
    extends
    filter
    makeScope
    mapAttrsToList
    packagesFromDirectoryRecursive
    optionalAttrs
    replaceStrings
    versionAtLeast
    versionOlder
    versions
    warnOnInstantiate
    ;

  cudaMajorMinorVersion = versions.majorMinor cudaMajorMinorPatchVersion;

  l4tMajorVersion = versions.major l4tMajorMinorPatchVersion;

  l4tAtLeast = versionAtLeast l4tMajorMinorPatchVersion;
  l4tOlder = versionOlder l4tMajorMinorPatchVersion;

  sourceInfo = import ./sourceinfo {
    inherit l4tMajorMinorPatchVersion;
    inherit (final) lib fetchurl fetchgit;
  };
in
makeScope final.newScope (self: {
  inherit (sourceInfo) debs gitRepos;
  inherit jetpackMajorMinorPatchVersion l4tMajorMinorPatchVersion cudaMajorMinorVersion;
  inherit l4tAtLeast l4tOlder;

  callPackages = callPackagesWith (final // self);

  bspSrc = final.runCommand "l4t-unpacked"
    {
      # https://developer.nvidia.com/embedded/jetson-linux-archive
      # https://repo.download.nvidia.com/jetson/
      src = final.fetchurl {
        url = "https://developer.download.nvidia.com/embedded/L4T/r${versions.major l4tMajorMinorPatchVersion}_Release_v${versions.minor l4tMajorMinorPatchVersion}.${versions.patch l4tMajorMinorPatchVersion}/release/Jetson_Linux_R${l4tMajorMinorPatchVersion}_aarch64.tbz2";
        hash = bspHash;
      };
      # We use a more recent version of bzip2 here because we hit this bug
      # extracting nvidia's archives:
      # https://bugs.launchpad.net/ubuntu/+source/bzip2/+bug/1834494
      nativeBuildInputs = [ final.buildPackages.bzip2_1_1 ];
    } ''
    bzip2 -d -c $src | tar xf -
    mv Linux_for_Tegra $out
  '';

  # Here for convenience, to see what is in upstream Jetpack
  unpackedDebs = final.runCommand "unpackedDebs-${l4tMajorMinorPatchVersion}" { nativeBuildInputs = [ final.buildPackages.dpkg ]; } ''
    mkdir -p $out
    ${concatMapAttrsStringSep "\n" (repo: debs: (concatMapAttrsStringSep "\n" (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") debs)) self.debs}
  '';

  # Also just for convenience,
  unpackedDebsFilenames = final.runCommand "unpackedDebsFilenames-${l4tMajorMinorPatchVersion}" { nativeBuildInputs = [ final.buildPackages.dpkg ]; } ''
    mkdir -p $out
    ${concatMapAttrsStringSep "\n" (repo: debs: (concatMapAttrsStringSep "\n" (n: p: "echo Extracting file list from ${n}; dpkg --fsys-tarfile ${p.src} | tar --list > $out/${n}") debs)) self.debs}
  '';

  unpackedGitRepos = final.runCommand "unpackedGitRepos-${l4tMajorMinorPatchVersion}" { } (
    mapAttrsToList
      (relpath: repo: ''
        mkdir -p $out/${relpath}
        cp --no-preserve=all -r ${repo}/. $out/${relpath}
      '')
      self.gitRepos
  );

  inherit (final.callPackages ./pkgs/uefi-firmware/r${l4tMajorVersion} { inherit (self) l4tMajorMinorPatchVersion; })
    uefi-firmware;

  inherit (final.callPackages ./pkgs/optee {
    inherit (self) bspSrc gitRepos l4tMajorMinorPatchVersion l4tOlder l4tAtLeast uefi-firmware;
  }) buildTOS buildOpteeTaDevKit opteeClient buildPkcs11Ta buildOpteeXtest;
  genEkb = self.callPackage ./pkgs/optee/gen-ekb.nix { };

  flash-tools = self.callPackage ./pkgs/flash-tools { };

  # Allows automation of Orin AGX devkit
  board-automation = self.callPackage ./pkgs/board-automation { };

  # Allows automation of Xavier AGX devkit
  python-jetson = final.python3.pkgs.callPackage ./pkgs/python-jetson { };

  tegra-eeprom-tool = final.callPackage ./pkgs/tegra-eeprom-tool { };
  tegra-eeprom-tool-static = final.pkgsStatic.callPackage ./pkgs/tegra-eeprom-tool { };

  # Taken largely from:
  # https://github.com/NixOS/nixpkgs/blob/b0401fdfb86201ed2e351665387ad6505b88f452/pkgs/top-level/cuda-packages.nix
  cudaPackages =
    let
      inherit (final) _cuda;
      inherit (self) cudaMajorMinorVersion;
      cudaLib = _cuda.lib;

      # We must use an instance of Nixpkgs where the CUDA package set we're building is the default; if we do not, members
      # of the versioned, non-default package sets may rely on (transitively) members of the default, unversioned CUDA
      # package set.
      # See `Using cudaPackages.pkgs` in doc/languages-frameworks/cuda.section.md for more information.
      pkgs' =
        let
          cudaPackagesUnversionedName = "cudaPackages";
          cudaPackagesMajorVersionName = cudaLib.mkVersionedName cudaPackagesUnversionedName (
            versions.major cudaMajorMinorVersion
          );
          cudaPackagesMajorMinorVersionName = cudaLib.mkVersionedName cudaPackagesUnversionedName cudaMajorMinorVersion;

          nvidiaJetpackUnversionedName = "nvidia-jetpack";
          nvidiaJetpackMajorVersionName = "${nvidiaJetpackUnversionedName}${versions.major jetpackMajorMinorPatchVersion}";
        in
        # If the CUDA version of pkgs matches our CUDA version, has the debs attribute (which is specific to
          # JetPack-constructed CUDA package sets), and the version of `nvidia-jetpack` matches, we are constructing
          # the default package set and can use pkgs without modification.
        if final.cudaPackages.cudaMajorMinorVersion == cudaMajorMinorVersion && final.cudaPackages ? debs &&
          final.nvidia-jetpack.jetpackMajorMinorPatchVersion == jetpackMajorMinorPatchVersion then
          final
        else
          final.extend (
            final: _: {
              recurseForDerivations = false;
              # The CUDA package set will be available as cudaPackages_x_y, so we need only update the aliases for the
              # minor-versioned and unversioned package sets.
              # cudaPackages_x = cudaPackages_x_y
              ${cudaPackagesMajorVersionName} = final.${cudaPackagesMajorMinorVersionName};
              # cudaPackages = cudaPackages_x
              ${cudaPackagesUnversionedName} = final.${cudaPackagesMajorVersionName};
              # nvidia-jetpack = nvidia-jetpackX
              # TODO(@cbaker2): This might have the assumption that final.${nvidiaJetpackMajorVersionName} *is* self.
              ${nvidiaJetpackUnversionedName} = final.${nvidiaJetpackMajorVersionName};
            }
          );

      passthruFunction = finalCudaPackages: {
        # Versions
        inherit cudaMajorMinorPatchVersion cudaMajorMinorVersion;
        cudaMajorVersion = versions.major finalCudaPackages.cudaMajorMinorVersion;
        cudaVersionDashes = replaceStrings [ "." ] [ "-" ] cudaMajorMinorVersion;

        # Utilities
        callPackages = callPackagesWith (pkgs' // pkgs'.nvidia-jetpack // finalCudaPackages);
        cudaAtLeast = versionAtLeast finalCudaPackages.cudaMajorMinorPatchVersion;
        cudaOlder = versionOlder finalCudaPackages.cudaMajorMinorPatchVersion;
        inherit (self) debs; # NOTE: The presence of debs is used as a condition in construciton of pkgs'.
        debsForSourcePackage = srcPackageName: filter (pkg: (pkg.source or "") == srcPackageName) (attrValues finalCudaPackages.debs.common);

        pkgs = pkgs';

        # Use backendStdenv from upstream
        backendStdenv = finalCudaPackages.callPackage (final.path + "/pkgs/development/cuda-modules/packages/backendStdenv.nix") { };

        # Include saxpy as a way to check functionality
        saxpy = finalCudaPackages.callPackage (final.path + "/pkgs/development/cuda-modules/packages/saxpy/package.nix") { };

        cudaNamePrefix = "cuda${cudaMajorMinorVersion}";

        flags =
          cudaLib.formatCapabilities
            {
              inherit (finalCudaPackages.backendStdenv) cudaCapabilities cudaForwardCompat;
              inherit (_cuda.db) cudaCapabilityToInfo;
            }
          // {
            inherit (cudaLib) dropDots;
            cudaComputeCapabilityToName =
              cudaCapability: _cuda.db.cudaCapabilityToInfo.${cudaCapability}.archName;
            dropDot = cudaLib.dropDots;
            isJetsonBuild = finalCudaPackages.backendStdenv.hasJetsonCudaCapability;
          };

        # NCCL is unavailable on Jetson devices.
        # We create an attribute for a broken derivation to avoid missing attribute evaluation errors.
        nccl = final.emptyFile.overrideAttrs {
          name = "nccl-is-unavailable-on-jetson-devices";
          meta.platforms = [ "x86_64-linux" ];
        };

        # The CUDA compatibility library is unavailable on JetPack relases because the CUDA driver and runtime versions match.
        # NOTE: Upstream may check for existence or nullity of cuda_compat, but does not explicitly check
        # meta.unavailable (which is unreliable anyway since meta is not checked recursively).
        cuda_compat = null;

        # Likewise, autoAddCudaCompatRunpath doesn't exist in the JetPack CUDA package set.
        autoAddCudaCompatRunpath = null;

        # Early releases of JetPack may not support or provide these packages.
        # Since later overlays may replace these, we can generically set them to null.
        cusparselt = null;
        libcufile = null;

        # Aliases
        # TODO(@connorbaker): Deprecation warnings.
        cudaFlags = finalCudaPackages.flags;
      } // optionalAttrs (versionOlder cudaMajorMinorPatchVersion "11.8") {
        # cuda_nvprof is expected to exist for CUDA versions prior to 11.8.
        # However, JetPack NixOS provides cuda_profiler_api, so just include a reference to that.
        # https://github.com/NixOS/nixpkgs/blob/9cb344e96d5b6918e94e1bca2d9f3ea1e9615545/pkgs/development/python-modules/torch/source/default.nix#L543-L545
        cuda_nvprof = finalCudaPackages.cuda_profiler_api;
      };

      composedExtensions = composeManyExtensions ([
        # Add the packages built from debians
        (finalCudaPackages: _: packagesFromDirectoryRecursive {
          directory = ./pkgs/cuda-packages;
          inherit (finalCudaPackages) callPackage;
        })
      ]
      ++ _cuda.extensions);
    in
    # NOTE: We must ensure the scope allows us to draw on the contents of nvidia-jetpack.
    makeScope pkgs'.nvidia-jetpack.newScope (
      extends composedExtensions passthruFunction
    );

  samples = makeScope self.newScope (finalSamples: {
    callPackages = callPackagesWith (self // finalSamples);
  } // packagesFromDirectoryRecursive {
    directory = ./pkgs/samples;
    inherit (finalSamples) callPackage;
  });

  tests = final.callPackages ./pkgs/tests { inherit l4tMajorMinorPatchVersion l4tAtLeast; };

  kernelPackagesOverlay = final: _:
    if self.l4tAtLeast "36" then {
      devicetree = final.callPackage ./pkgs/kernels/r${l4tMajorVersion}/devicetree.nix { inherit (self) bspSrc gitRepos l4tMajorMinorPatchVersion; };
      nvidia-oot-modules = final.callPackage ./pkgs/kernels/r${l4tMajorVersion}/oot-modules.nix { inherit (self) bspSrc gitRepos l4tMajorMinorPatchVersion; };
    } else {
      nvidia-display-driver = final.callPackage ./pkgs/kernels/r${l4tMajorVersion}/display-driver.nix { inherit (self) gitRepos l4tMajorMinorPatchVersion; };
    };

  kernel = self.callPackage ./pkgs/kernels/r${l4tMajorVersion} { kernelPatches = [ ]; };
  kernelPackages = final.linuxPackagesFor self.kernel;

  rtkernel = self.callPackage ./pkgs/kernels/r${l4tMajorVersion} { kernelPatches = [ ]; realtime = true; };
  rtkernelPackages = final.linuxPackagesFor self.rtkernel;

  nxJetsonBenchmarks = self.callPackage ./pkgs/jetson-benchmarks {
    targetSom = "nx";
  };
  xavierAgxJetsonBenchmarks = self.callPackage ./pkgs/jetson-benchmarks {
    targetSom = "xavier-agx";
  };
  orinAgxJetsonBenchmarks = self.callPackage ./pkgs/jetson-benchmarks {
    targetSom = "orin-agx";
  };

  flashFromDevice = self.callPackage ./pkgs/flash-from-device { };

  otaUtils = self.callPackage ./pkgs/ota-utils { };

  l4tCsv = self.callPackage ./pkgs/containers/l4t-csv.nix { };
  genL4tJson = final.runCommand "l4t.json" { nativeBuildInputs = [ final.buildPackages.python3 ]; } ''
    python3 ${./pkgs/containers/gen_l4t_json.py} ${self.l4tCsv} ${self.unpackedDebsFilenames} > $out
  '';
  containerDeps = self.callPackage ./pkgs/containers/deps.nix { };
  nvidia-ctk = warnOnInstantiate "nvidia-jetpack.nvidia-ctk has been removed, use pkgs.nvidia-container-toolkit" final.nvidia-container-toolkit;

  # TODO(jared): deprecate this
  devicePkgsFromNixosConfig = config: config.system.build.jetsonDevicePkgs;
}
  # Add the L4T packages
  # NOTE: Since this is adding packages to the top-level, and callPackage's auto args functionality draws from that
  # attribute set, we cannot use self.callPackages because we would end up with infinite recursion.
  # Instead, we must either use final.callPackages or packagesFromDirectoryRecursive.
  // final.callPackages ./pkgs/l4t {
  inherit (self) debs;
  inherit l4tMajorMinorPatchVersion cudaDriverMajorMinorVersion l4tAtLeast l4tOlder;
})
