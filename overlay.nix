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

  # Due to the interplay between JetPack releases and supported CUDA versions, the choice of CUDA version drives the
  # version of nvidia-jetpack made the default to avoid the need to maintain tedious overlays and ensures the two stay
  # in sync by default.
  #
  # Thanks to the functionality added in https://github.com/NixOS/nixpkgs/pull/406568, we can build packages
  # using variants of Nixpkgs through the Flake CLI. See https://nixos.org/manual/nixpkgs/stable/#cuda-using-cudapackages-pkgs
  # for an example.
  #
  # Consider a user trying to build a hypothetical package foo which works with all versions of nvidia-jetpack. If
  # they build .#blarg (assuming proper configuration of Nixpkgs and use of our overlay), blarg receives
  # nvidia-jetpack5 as nvidia-jetpack and nvidia-jetpack5.cudaPackages (CUDA 11.4) as cudaPackages.
  # If they build .#cudaPackages_12.pkgs.blarg, blarg receives nvidia-jetpack6 as nvidia-jetpack and
  # nvidia-jetpack6.cudaPackages (CUDA 12.6) as cudaPackages. If the version of nvidia-jetpack did not depend on
  # the version of the CUDA package set, blarg would have received nvidia-jetpack5 as nvidia-jetpack (since it would
  # stay unchanged) and nvidia-jetpack6.cudaPackages (CUDA 12.6) as cudaPackages -- this is likely unintentional!
  nvidia-jetpack =
    # Support for pre-11.4 belongs with JetPack 4, which is no longer maintained.
    # CUDA 11.4 - 12.2 is supported either natively (11.4) or through cuda_compat (everything else).
    if final.cudaPackages.cudaOlder "12.3" then
      final.nvidia-jetpack5

    # CUDA 12.4 - 12.9 is supported either natively (12.4) or through cuda_compat (everything else).
    # CUDA 13.0+ is supported by JetPack 7, which we don't yet package.
    # NOTE: CUDA 12.3 isn't supported by JetPack 5 or 6, but we lump it in with JetPack 6 to avoid throwing.
    else
      final.nvidia-jetpack6;

  # Set cudaPackage package sets to our JetPack-constructed package sets if we are targeting Jetson capabilities.
  # NOTE: We cannot lift the conditionals out further without causing infinite recursion, as the fixed-point would be
  # used to determine the presence/absence of attributes.
  cudaPackages_11_4 =
    if redistSystem == "linux-aarch64" then
      assert final.nvidia-jetpack5.cudaPackages.cudaMajorMinorVersion == "11.4";
      final.nvidia-jetpack5.cudaPackages
    else
      prev.cudaPackages_11_4;
  cudaPackages_11 =
    if redistSystem == "linux-aarch64" then
      final.cudaPackages_11_4
    else
      prev.cudaPackages_11;

  cudaPackages_12_6 =
    if redistSystem == "linux-aarch64" then
      assert final.nvidia-jetpack6.cudaPackages.cudaMajorMinorVersion == "12.6";
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
