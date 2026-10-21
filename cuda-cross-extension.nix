# Makes NVCC usable when cross-compiling from x86_64-linux for a Jetson device.
#
# When cross-compiling, packages which place `cudaPackages.cuda_nvcc` in `nativeBuildInputs` receive it from the CUDA
# package set of `pkgsBuildHost`: one which runs on x86_64-linux, but which is instantiated with the same
# `config.cudaCapabilities` as the target. Upstream's `backendStdenv` asserts that Jetson capabilities are only requested
# by aarch64-linux hosts, which is true of the libraries in the package set, but not of NVCC, which is a compiler.
#
# NVIDIA supports this configuration directly: their x86_64 NVCC, given an aarch64 host compiler, produces objects for
# Jetson devices (see the `cuda-cross-aarch64` packages in NVIDIA's apt repositories). This extension:
#
# - replaces `backendStdenv` in CUDA package sets which request Jetson capabilities but do not run on aarch64-linux with
#   one which does not make that assertion, but otherwise describes the requested capabilities. Splicing evaluates the
#   package sets of every stage (including `pkgsBuildBuild`, which is indistinguishable from a native x86_64-linux
#   instance of Nixpkgs), so all of them must evaluate;
# - for those package sets which also target aarch64-linux (e.g., `pkgsBuildHost`), points `cuda_nvcc` and
#   `setupCudaHook` at the Jetson's backend compiler, so NVCC compiles host code for aarch64-linux;
# - for CUDA 11.4, replaces `cuda_nvcc` in those package sets with the x86_64-linux release matching the version shipped
#   by JetPack 5.
#
# All other packages are left as-is; libraries must still come from the target package set (i.e., `buildInputs`).
#
# NOTE: `pkgs` must be the instance of Nixpkgs the CUDA package set is created in, not the package set's `pkgs`
# attribute: the latter depends on the package set's manifests, which depend on `backendStdenv`.
{ pkgs }:
finalCudaPackages: prevCudaPackages:
let
  inherit (pkgs) _cuda lib;
  inherit (pkgs.stdenv) hostPlatform targetPlatform;
  inherit (lib)
    filter
    getAttr
    optionalAttrs
    ;

  inherit (prevCudaPackages) cudaMajorMinorVersion;

  cudaCapabilities = pkgs.config.cudaCapabilities or [ ];
  requestedCudaCapabilitiesWhere = predicate:
    filter (cudaCapability: predicate _cuda.db.cudaCapabilityToInfo.${cudaCapability}) cudaCapabilities;

  requestedJetsonCudaCapabilities = requestedCudaCapabilitiesWhere (info: info.isJetson);
  requestedArchitectureSpecificCudaCapabilities = requestedCudaCapabilitiesWhere (info: info.isArchitectureSpecific);
  requestedFamilySpecificCudaCapabilities = requestedCudaCapabilitiesWhere (info: info.isFamilySpecific);

  isJetsonBuildPackageSet = requestedJetsonCudaCapabilities != [ ] && !hostPlatform.isAarch64;

  # Construct upstream's backendStdenv without requesting any CUDA capabilities, which passes the assertions. Then
  # restore the requested capabilities, so flags and manifest selection are consistent with the Jetson's package set.
  # NOTE: This mirrors the computation of these attributes in upstream's backendStdenv.
  backendStdenv =
    (import "${pkgs.path}/pkgs/development/cuda-modules/backendStdenv" {
      inherit _cuda cudaMajorMinorVersion lib pkgs;
      inherit (pkgs) stdenv stdenvAdapters;
      config = pkgs.config // { cudaCapabilities = [ ]; };
    }).override (prevArgs: {
      extraAttrs = prevArgs.extraAttrs // {
        inherit
          cudaCapabilities
          requestedArchitectureSpecificCudaCapabilities
          requestedFamilySpecificCudaCapabilities
          requestedJetsonCudaCapabilities
          ;
        hasArchitectureSpecificCudaCapability = requestedArchitectureSpecificCudaCapabilities != [ ];
        hasFamilySpecificCudaCapability = requestedFamilySpecificCudaCapabilities != [ ];
        hasJetsonCudaCapability = true;
      };
    });

  # The CUDA package set of the same version which runs on the Jetson.
  targetCudaPackages = getAttr (_cuda.lib.mkVersionedName "cudaPackages" cudaMajorMinorVersion) pkgs.targetPackages;
  targetBackendStdenv = targetCudaPackages.backendStdenv;

  # NVCC accepts the path to a host compiler executable in place of a directory, which lets us use the cross-compiler's
  # prefixed binaries. NVCC uses the host compiler for both C and C++, so we point it at the C++ compiler.
  targetHostCompiler = "${targetBackendStdenv.cc}/bin/${targetBackendStdenv.cc.targetPrefix}c++";

  retargetCudaNvcc = drv: drv.overrideAttrs (prevAttrs: {
    # NVCC provides headers required by host code which includes the CUDA runtime headers (e.g., crt/host_config.h).
    # When NVCC is in nativeBuildInputs, these are only visible to NVCC itself, so propagate the Jetson's NVCC to
    # consumers' buildInputs, making its headers available to the host compiler.
    depsTargetTargetPropagated = prevAttrs.depsTargetTargetPropagated or [ ] ++ [ targetCudaPackages.cuda_nvcc ];

    postInstall = prevAttrs.postInstall or "" + ''
      nixLog "setting compiler-bindir to ${targetHostCompiler} in nvcc.profile"
      substituteInPlace "''${!outputBin:?}/bin/nvcc.profile" \
        --replace-fail \
          "compiler-bindir = ${targetBackendStdenv.cc}/bin" \
          "compiler-bindir = ${targetHostCompiler}"
    '';
  });

  # NOTE: The x86_64 NVCC release for JetPack 5 is only available as a debian installer from NVIDIA's x86_64 Jetson
  # repository. Upstream's x86_64-linux CUDA 11.4 release ships an older NVCC (11.4.152).
  # Hashes are taken from:
  # https://repo.download.nvidia.com/jetson/x86_64/focal/dists/r35.6/main/binary-amd64/Packages.gz
  setCudaNvcc_11_4_Source = drv: drv.overrideAttrs (finalAttrs: prevAttrs: {
    version = "11.4.315";
    src = finalCudaPackages.normalizeDebs {
      srcs = [
        (pkgs.fetchurl {
          url = "https://repo.download.nvidia.com/jetson/x86_64/focal/pool/main/c/cuda-nvcc/cuda-nvcc-11-4_11.4.315-1_amd64.deb";
          sha256 = "c6af78a9f24aea33dfcbe1fef280a40062688a749418f75fcbf164c770c4e764";
        })
      ];
      inherit (finalAttrs) version;
      pname = finalAttrs.pname + "-debs";
    };
    # The documentation and copyright notices contain FHS references.
    allowFHSReferences = true;
    passthru = prevAttrs.passthru // {
      # Doesn't come from a release manifest.
      release = null;
      supportedNixSystems = [ "x86_64-linux" ];
      supportedRedistSystems = [ "linux-x86_64" ];
    };
  });
in
optionalAttrs isJetsonBuildPackageSet
  {
    inherit backendStdenv;
  }
  // optionalAttrs (isJetsonBuildPackageSet && targetPlatform.isAarch64) {
  cuda_nvcc =
    let
      cuda_nvcc = prevCudaPackages.cuda_nvcc.override { backendStdenv = targetBackendStdenv; };
    in
    retargetCudaNvcc (if cudaMajorMinorVersion == "11.4" then setCudaNvcc_11_4_Source cuda_nvcc else cuda_nvcc);

  setupCudaHook = prevCudaPackages.setupCudaHook.override { backendStdenv = targetBackendStdenv; };
}
