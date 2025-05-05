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

  nvidia-jetpack6 = import ./mk-overlay.nix
    {
      # Below 3 are from release notes
      jetpackMajorMinorPatchVersion = "6.2";
      l4tMajorMinorPatchVersion = "36.4.3";
      cudaMajorMinorPatchVersion = "12.6.10";

      bspHash = "sha256-lJpEBJxM5qjv31cuoIIMh09u5dQco+STW58OONEYc9I=";
    }
    final
    prev;

  nvidia-jetpack = final.nvidia-jetpack5;
}
