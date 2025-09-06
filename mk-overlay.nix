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
    callPackagesWith
    concatStringsSep
    filter
    makeScope
    mapAttrsToList
    packagesFromDirectoryRecursive
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
    ${concatStringsSep "\n" (mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") self.debs.common)}
    ${concatStringsSep "\n" (mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") self.debs.t234)}
  '';

  # Also just for convenience,
  unpackedDebsFilenames = final.runCommand "unpackedDebsFilenames-${l4tMajorMinorPatchVersion}" { nativeBuildInputs = [ final.buildPackages.dpkg ]; } ''
    mkdir -p $out
    ${concatStringsSep "\n" (mapAttrsToList (n: p: "echo Extracting file list from ${n}; dpkg --fsys-tarfile ${p.src} | tar --list > $out/${n}") self.debs.common)}
    ${concatStringsSep "\n" (mapAttrsToList (n: p: "echo Extracting file list from ${n}; dpkg --fsys-tarfile ${p.src} | tar --list > $out/${n}") self.debs.t234)}
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
    edk2-jetson uefi-firmware;

  inherit (final.callPackages ./pkgs/optee {
    # As today as this comment is written then nixpkgs unstabble has removed
    # gcc12Stdenv and below support. The next "oldest" is gcc13Stdenv.
    #
    # Jetson 36.x; Anticipating upcomming nixpkgs updates and
    # therefore swithching directly to use gcc13Stdenv. Officially NVIDIA
    # uses gcc11
    #
    # Jetson 35.x: Keeping gcc9 as per NVIDIA recommends
    stdenv = if self.l4tAtLeast "36" then final.gcc13Stdenv else final.gcc9Stdenv;
    inherit (self) bspSrc gitRepos l4tMajorMinorPatchVersion l4tAtLeast uefi-firmware;
  }) buildTOS buildOpteeTaDevKit opteeClient;
  genEkb = self.callPackage ./pkgs/optee/gen-ekb.nix { };

  flash-tools = self.callPackage ./pkgs/flash-tools { };

  # Allows automation of Orin AGX devkit
  board-automation = self.callPackage ./pkgs/board-automation { };

  # Allows automation of Xavier AGX devkit
  python-jetson = final.python3.pkgs.callPackage ./pkgs/python-jetson { };

  tegra-eeprom-tool = final.callPackage ./pkgs/tegra-eeprom-tool { };
  tegra-eeprom-tool-static = final.pkgsStatic.callPackage ./pkgs/tegra-eeprom-tool { };

  cudaPackages = makeScope self.newScope (finalCudaPackages: {
    # Versions
    inherit cudaMajorMinorPatchVersion cudaMajorMinorVersion;
    cudaMajorVersion = versions.major finalCudaPackages.cudaMajorMinorVersion;
    cudaVersionDashes = replaceStrings [ "." ] [ "-" ] cudaMajorMinorVersion;

    # Utilities
    callPackages = callPackagesWith (self // finalCudaPackages);
    cudaAtLeast = versionAtLeast finalCudaPackages.cudaMajorMinorPatchVersion;
    cudaOlder = versionOlder finalCudaPackages.cudaMajorMinorPatchVersion;
    inherit (self) debs;
    debsForSourcePackage = srcPackageName: filter (pkg: (pkg.source or "") == srcPackageName) (attrValues finalCudaPackages.debs.common);

    # Aliases
    # TODO(@connorbaker): Deprecation warnings.
    cudaFlags = finalCudaPackages.flags;
  }
  # Add the packages built from debians
  // packagesFromDirectoryRecursive {
    directory = ./pkgs/cuda-packages;
    inherit (finalCudaPackages) callPackage;
  });

  samples = makeScope self.newScope (finalSamples: {
    callPackages = callPackagesWith (self // finalSamples);
  } // packagesFromDirectoryRecursive {
    directory = ./pkgs/samples;
    inherit (finalSamples) callPackage;
  });

  tests = final.callPackages ./pkgs/tests { inherit l4tMajorMinorPatchVersion l4tAtLeast; };

  kernelPackagesOverlay = final: _:
    if self.l4tAtLeast "36" then {
      devicetree = self.callPackage ./pkgs/kernels/r${l4tMajorVersion}/devicetree.nix { };
      nvidia-oot-modules = final.callPackage ./pkgs/kernels/r${l4tMajorVersion}/oot-modules.nix { inherit (self) bspSrc gitRepos l4tMajorMinorPatchVersion; };
    } else {
      nvidia-display-driver = final.callPackage ./pkgs/kernels/r${l4tMajorVersion}/display-driver.nix { inherit (self) gitRepos l4tMajorMinorPatchVersion; };
    };

  kernel = self.callPackage ./pkgs/kernels/r${l4tMajorVersion} { kernelPatches = [ ]; };
  kernelPackages = (final.linuxPackagesFor self.kernel).extend self.kernelPackagesOverlay;

  rtkernel = self.callPackage ./pkgs/kernels/r${l4tMajorVersion} { kernelPatches = [ ]; realtime = true; };
  rtkernelPackages = (final.linuxPackagesFor self.rtkernel).extend self.kernelPackagesOverlay;

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
