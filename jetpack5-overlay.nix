import ./mk-overlay.nix {
  # Below 3 are from release notes
  jetpackMajorMinorPatchVersion = "5.1.5";
  l4tMajorMinorPatchVersion = "35.6.1";
  cudaMajorMinorPatchVersion = "11.4.298";

  # used to version libnvidia-ptxjitcompiler.so. L4T r35 uses l4tMajorMinorPatchVersion, so set to null
  # and we'll use l4tMajorMinorPatchVersion instead
  cudaDriverMajorMinorVersion = null;

  bspHash = "sha256-nqKEd3R7MJXuec3Q4odDJ9SNTUD1FyluWg/SeeptbUE=";
}
