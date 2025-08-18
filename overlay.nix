final: prev:
let
  inherit (final.lib)
    filter
    intersectLists
    recursiveUpdate
    ;

  # Taken largely from:
  # https://github.com/NixOS/nixpkgs/blob/b0401fdfb86201ed2e351665387ad6505b88f452/pkgs/top-level/cuda-packages.nix

  inherit (final) _cuda;

  # Since Jetson capabilities are never built by default, we can check if any of them were requested
  # through final.config.cudaCapabilities and use that to determine if we should change some manifest versions.
  # Copied from backendStdenv.
  jetsonCudaCapabilities = filter
    (
      cudaCapability: _cuda.db.cudaCapabilityToInfo.${cudaCapability}.isJetson
    )
    _cuda.db.allSortedCudaCapabilities;
  hasJetsonCudaCapability =
    intersectLists jetsonCudaCapabilities (final.config.cudaCapabilities or [ ]) != [ ];
  redistSystem = _cuda.lib.getRedistSystem hasJetsonCudaCapability final.stdenv.hostPlatform.system;
in
{
  nvidia-jetpack5 = import ./mk-overlay.nix
    {
      # Below 3 are from release notes
      jetpackMajorMinorPatchVersion = "5.1.5";
      l4tMajorMinorPatchVersion = "35.6.2";
      cudaMajorMinorPatchVersion = "11.4.298";

      # used to version libnvidia-ptxjitcompiler.so. L4T r35 uses l4tMajorMinorPatchVersion, so set to null
      # and we'll use l4tMajorMinorPatchVersion instead
      cudaDriverMajorMinorVersion = null;

      bspHash = "sha256-u+dRtBHhN+bxwiuGlZwEhSXrpSfSb+kuC50+FjobSTg=";
    }
    final
    prev;

  nvidia-jetpack6 = import ./mk-overlay.nix
    {
      # Below 3 are from release notes
      jetpackMajorMinorPatchVersion = "6.2.1";
      l4tMajorMinorPatchVersion = "36.4.4";
      cudaMajorMinorPatchVersion = "12.6.10";

      # nix build .#legacyPacakges.l4t-cuda.src; unpack the deb; find libnvidia-ptxjijtcompiler.so
      # and use that.
      cudaDriverMajorMinorVersion = "540.4.0";

      bspHash = "sha256-ps4RwiEAqwl25BmVkYJBfIPWL0JyUBvIcU8uB24BDzs=";
    }
    final
    prev;

  # The choice of CUDA version drives the version of nvidia-jetpack made the default. If the default version of the
  # CUDA package set is one of our JetPack-constructed CUDA package sets, choose a version of nvidia-jetpack
  # accordingly. If it is not, default to nvidia-jetpack5.
  nvidia-jetpack =
    if final.cudaPackages ? debs then
      if (assert final.nvidia-jetpack5.cudaPackages.cudaMajorMinorVersion == "11.4"; final.cudaPackages.cudaMajorMinorVersion == "11.4") then
        final.nvidia-jetpack5
      else if (assert final.nvidia-jetpack6.cudaPackages.cudaMajorMinorVersion == "12.6"; final.cudaPackages.cudaMajorMinorVersion == "12.6") then
        final.nvidia-jetpack6
      else
        builtins.throw "unrecognized cudaPackages (version ${final.cudaPackages.cudaMajorMinorVersion}) providing `debs` attribute"
    else
      final.nvidia-jetpack5;


  # Set cudaPackage package sets to our JetPack-constructed package sets if we are targeting Jetson capabilities.
  # NOTE: We cannot lift the conditionals out further without causing infinite recursion, as the fixed-point would be
  # used to determine the presence/absence of attributes.
  cudaPackages_11_4 =
    assert final.nvidia-jetpack5.cudaPackages.cudaMajorMinorVersion == "11.4";
    if redistSystem == "linux-aarch64" then
      final.nvidia-jetpack5.cudaPackages
    else
      prev.cudaPackages_11_4;
  cudaPackages_11 =
    if redistSystem == "linux-aarch64" then
      final.cudaPackages_11_4
    else
      prev.cudaPackages_11;

  cudaPackages_12_6 =
    assert final.nvidia-jetpack6.cudaPackages.cudaMajorMinorVersion == "12.6";
    if redistSystem == "linux-aarch64" then
      final.nvidia-jetpack6.cudaPackages
    else
      prev.cudaPackages_12_6;
  cudaPackages_12 =
    if redistSystem == "linux-aarch64" then
      final.cudaPackages_12_6
    else
      prev.cudaPackages_12;

  cudaPackages = final.cudaPackages_11;

  # Update _cuda's database with an entry allowing Orin on CUDA 11.4.
  _cuda = prev._cuda.extend (final: prev: recursiveUpdate prev {
    bootstrapData.cudaCapabilityToInfo."8.7".minCudaMajorMinorVersion = "11.4";
  });
}
