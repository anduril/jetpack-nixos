final: prev:
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
      jetpackMajorMinorPatchVersion = "6.2";
      l4tMajorMinorPatchVersion = "36.4.3";
      cudaMajorMinorPatchVersion = "12.6.10";

      # nix build .#legacyPacakges.l4t-cuda.src; unpack the deb; find libnvidia-ptxjijtcompiler.so
      # and use that.
      cudaDriverMajorMinorVersion = "540.4.0";

      bspHash = "sha256-lJpEBJxM5qjv31cuoIIMh09u5dQco+STW58OONEYc9I=";
    }
    final
    prev;

  nvidia-jetpack = final.nvidia-jetpack5;
}
