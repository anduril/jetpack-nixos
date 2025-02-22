# TODO(jared): Get rid of usage of `callPackages` where possible so we can take
# advantage of scope's `self.callPackage` (callPackages does not exist under
# `self`).

final: prev:
let
  jetpackVersion = "5.1.4";
  l4tVersion = "35.6.0";
  cudaVersion = "11.4";

  sourceInfo = import ./sourceinfo {
    inherit l4tVersion;
    inherit (prev) lib fetchurl fetchgit;
  };
in
{
  nvidia-jetpack = prev.lib.makeScope prev.newScope (self: ({
    inherit jetpackVersion l4tVersion cudaVersion;

    inherit (sourceInfo) debs gitRepos;

    bspSrc = prev.runCommand "l4t-unpacked"
      {
        # https://developer.nvidia.com/embedded/jetson-linux-archive
        # https://repo.download.nvidia.com/jetson/
        src = prev.fetchurl {
          url = with prev.lib.versions; "https://developer.download.nvidia.com/embedded/L4T/r${major l4tVersion}_Release_v${minor l4tVersion}.${patch l4tVersion}/release/Jetson_Linux_R${l4tVersion}_aarch64.tbz2";
          hash = "sha256-HMB+qUbfBksetda6i8KJ2E5rn0N7X1OOlaDSrmY55gE=";
        };
        # We use a more recent version of bzip2 here because we hit this bug
        # extracting nvidia's archives:
        # https://bugs.launchpad.net/ubuntu/+source/bzip2/+bug/1834494
        nativeBuildInputs = [ prev.buildPackages.bzip2_1_1 ];
      } ''
      bzip2 -d -c $src | tar xf -
      mv Linux_for_Tegra $out
    '';

    # Here for convenience, to see what is in upstream Jetpack
    unpackedDebs = prev.runCommand "unpackedDebs-${l4tVersion}" { nativeBuildInputs = [ prev.buildPackages.dpkg ]; } ''
      mkdir -p $out
      ${prev.lib.concatStringsSep "\n" (prev.lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") self.debs.common)}
      ${prev.lib.concatStringsSep "\n" (prev.lib.mapAttrsToList (n: p: "echo Unpacking ${n}; dpkg -x ${p.src} $out/${n}") self.debs.t234)}
    '';

    # Also just for convenience,
    unpackedDebsFilenames = prev.runCommand "unpackedDebsFilenames-${l4tVersion}" { nativeBuildInputs = [ prev.buildPackages.dpkg ]; } ''
      mkdir -p $out
      ${prev.lib.concatStringsSep "\n" (prev.lib.mapAttrsToList (n: p: "echo Extracting file list from ${n}; dpkg --fsys-tarfile ${p.src} | tar --list > $out/${n}") self.debs.common)}
      ${prev.lib.concatStringsSep "\n" (prev.lib.mapAttrsToList (n: p: "echo Extracting file list from ${n}; dpkg --fsys-tarfile ${p.src} | tar --list > $out/${n}") self.debs.t234)}
    '';

    unpackedGitRepos = prev.runCommand "unpackedGitRepos-${l4tVersion}" { } (
      prev.lib.mapAttrsToList
        (relpath: repo: ''
          mkdir -p $out/${relpath}
          cp --no-preserve=all -r ${repo}/. $out/${relpath}
        '')
        self.gitRepos
    );

    edk2NvidiaSrc = self.callPackage ./pkgs/uefi-firmware/edk2-nvidia-src.nix { };
    jetsonEdk2Uefi = self.callPackage ./pkgs/uefi-firmware/jetson-edk2-uefi.nix { };
    uefiFirmware = self.callPackage ./pkgs/uefi-firmware/default.nix { };

    # Nvidia's recommended toolchain for optee is gcc9:
    # https://nv-tegra.nvidia.com/r/gitweb?p=tegra/optee-src/nv-optee.git;a=blob;f=optee/atf_and_optee_README.txt;h=591edda3d4ec96997e054ebd21fc8326983d3464;hb=5ac2ab218ba9116f1df4a0bb5092b1f6d810e8f7#l33
    opteeStdenv = prev.gcc9Stdenv;

    opteeClient = self.callPackage ./pkgs/optee/client.nix { };

    opteeTaDevKit = (self.callPackage ./pkgs/optee/os.nix { }).overrideAttrs (old: {
      pname = "optee-ta-dev-kit";
      makeFlags = (old.makeFlags or [ ]) ++ [ "ta_dev_kit" ];
    });

    nvLuksSrv = self.callPackage ./pkgs/optee/nv-luks-srv.nix { };
    hwKeyAgent = self.callPackage ./pkgs/optee/hw-key-agent.nix { };

    opteeOS = self.callPackage ./pkgs/optee/os.nix {
      earlyTaPaths = [
        "${self.nvLuksSrv}/${self.nvLuksSrv.uuid}.stripped.elf"
        "${self.hwKeyAgent}/${self.hwKeyAgent.uuid}.stripped.elf"
      ];
    };

    flash-tools = self.callPackage ./pkgs/flash-tools { };

    # Allows automation of Orin AGX devkit
    board-automation = self.callPackage ./pkgs/board-automation { };

    # Allows automation of Xavier AGX devkit
    python-jetson = prev.python3.pkgs.callPackage ./pkgs/python-jetson { };

    tegra-eeprom-tool = prev.callPackage ./pkgs/tegra-eeprom-tool { };
    tegra-eeprom-tool-static = prev.pkgsStatic.callPackage ./pkgs/tegra-eeprom-tool { };

    cudaPackages = prev.callPackages ./pkgs/cuda-packages {
      inherit (self) debs cudaVersion
        l4t-3d-core
        l4t-core
        l4t-cuda
        l4t-cupva
        l4t-multimedia;
      inherit (prev) autoAddDriverRunpath;
    };

    samples = prev.callPackages ./pkgs/samples {
      inherit (self) debs cudaVersion cudaPackages l4t-cuda l4t-multimedia l4t-camera;
      inherit (prev) autoAddDriverRunpath;
    };

    tests = prev.callPackages ./pkgs/tests { inherit l4tVersion; };

    kernelPackagesOverlay = final: prev: {
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
    genL4tJson = prev.runCommand "l4t.json" { nativeBuildInputs = [ prev.buildPackages.python3 ]; } ''
      python3 ${./pkgs/containers/gen_l4t_json.py} ${self.l4tCsv} ${self.unpackedDebsFilenames} > $out
    '';
    containerDeps = self.callPackage ./pkgs/containers/deps.nix { };
    nvidia-ctk = self.callPackage ./pkgs/containers/nvidia-ctk.nix { };

    # TODO(jared): deprecate this
    devicePkgsFromNixosConfig = config: config.system.build.jetsonDevicePkgs;
  } // (prev.callPackages ./pkgs/l4t {
    inherit l4tVersion;
    inherit (sourceInfo) debs;
  })));
}
