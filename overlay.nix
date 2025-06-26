final: prev:
{
  nvidia-jetpack5 = import ./mk-overlay.nix
    {
      # Below 3 are from release notes
      jetpackMajorMinorPatchVersion = "5.1.5";
      l4tMajorMinorPatchVersion = "35.6.1";
      cudaMajorMinorPatchVersion = "11.4.298";

      bspHash = "sha256-nqKEd3R7MJXuec3Q4odDJ9SNTUD1FyluWg/SeeptbUE=";
    }
    final
    prev;

  nvidia-jetpack = final.nvidia-jetpack5;
}
