# TODO(jared): Get rid of usage of `callPackages` where possible so we can take
# advantage of scope's `self.callPackage` (callPackages does not exist under
# `self`).

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
    ;

  jetpackVersion = "5.1.5";
  l4tVersion = "35.6.1";
  cudaMajorMinorPatchVersion = "11.4.298";
  cudaVersion = versions.majorMinor cudaMajorMinorPatchVersion;

  sourceInfo = import ./sourceinfo {
    inherit l4tVersion;
    inherit (final) lib fetchurl fetchgit;
  };
in
{
  nvidia-jetpack = makeScope final.newScope (self: {
    inherit (sourceInfo) debs gitRepos;
    inherit jetpackVersion l4tVersion cudaVersion;

    callPackages = callPackagesWith (final // self);

    bspSrc = final.runCommand "l4t-unpacked"
      {
        # https://developer.nvidia.com/embedded/jetson-linux-archive
        # https://repo.download.nvidia.com/jetson/
        src = final.fetchurl {
          url = "https://developer.download.nvidia.com/embedded/L4T/r${versions.major l4tVersion}_Release_v${versions.minor l4tVersion}.${versions.patch l4tVersion}/release/Jetson_Linux_R${l4tVersion}_aarch64.tbz2";
          hash = "sha256-nqKEd3R7MJXuec3Q4odDJ9SNTUD1FyluWg/SeeptbUE=";
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
    unpackedDebs = final.runCommand "unpackedDebs-${l4tVersion}" { nativeBuildInputs = [ final.buildPackages.dpkg ]; } ''
      mkdir -p $out
      ${concatStringsSep "\n" (mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") self.debs.common)}
      ${concatStringsSep "\n" (mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") self.debs.t234)}
    '';

    # Also just for convenience,
    unpackedDebsFilenames = final.runCommand "unpackedDebsFilenames-${l4tVersion}" { nativeBuildInputs = [ final.buildPackages.dpkg ]; } ''
      mkdir -p $out
      ${concatStringsSep "\n" (mapAttrsToList (n: p: "echo Extracting file list from ${n}; dpkg --fsys-tarfile ${p.src} | tar --list > $out/${n}") self.debs.common)}
      ${concatStringsSep "\n" (mapAttrsToList (n: p: "echo Extracting file list from ${n}; dpkg --fsys-tarfile ${p.src} | tar --list > $out/${n}") self.debs.t234)}
    '';

    unpackedGitRepos = final.runCommand "unpackedGitRepos-${l4tVersion}" { } (
      mapAttrsToList
        (relpath: repo: ''
          mkdir -p $out/${relpath}
          cp --no-preserve=all -r ${repo}/. $out/${relpath}
        '')
        self.gitRepos
    );

    inherit (final.callPackages ./pkgs/uefi-firmware { inherit (self) l4tVersion; })
      edk2-jetson uefi-firmware;

    inherit (final.callPackages ./pkgs/optee {
      # Nvidia's recommended toolchain is gcc9:
      # https://nv-tegra.nvidia.com/r/gitweb?p=tegra/optee-src/nv-optee.git;a=blob;f=optee/atf_and_optee_README.txt;h=591edda3d4ec96997e054ebd21fc8326983d3464;hb=5ac2ab218ba9116f1df4a0bb5092b1f6d810e8f7#l33
      stdenv = final.gcc9Stdenv;
      inherit (self) bspSrc gitRepos l4tVersion uefi-firmware;
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
      inherit (self) cudaVersion;
      inherit cudaMajorMinorPatchVersion;
      cudaMajorMinorVersion = finalCudaPackages.cudaVersion;
      cudaMajorVersion = versions.major finalCudaPackages.cudaVersion;
      cudaVersionDashes = replaceStrings [ "." ] [ "-" ] cudaVersion;

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

    tests = final.callPackages ./pkgs/tests { inherit l4tVersion; };

    kernelPackagesOverlay = final: _: {
      nvidia-display-driver = final.callPackage ./kernel/display-driver.nix { inherit (self) gitRepos l4tVersion; };
    };

    kernel = self.callPackage ./kernel { kernelPatches = [ ]; };
    kernelPackages = (final.linuxPackagesFor self.kernel).extend self.kernelPackagesOverlay;

    rtkernel = self.callPackage ./kernel { kernelPatches = [ ]; realtime = true; };
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
    nvidia-ctk = self.callPackage ./pkgs/containers/nvidia-ctk.nix { };

    # TODO(jared): deprecate this
    devicePkgsFromNixosConfig = config: config.system.build.jetsonDevicePkgs;
  }
  # Add the L4T packages
  # NOTE: Since this is adding packages to the top-level, and callPackage's auto args functionality draws from that
  # attribute set, we cannot use self.callPackages because we would end up with infinite recursion.
  # Instead, we must either use final.callPackages or packagesFromDirectoryRecursive.
  // final.callPackages ./pkgs/l4t {
    inherit (self) debs l4tVersion;
  });
}
