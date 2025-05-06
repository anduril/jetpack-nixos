import ./mk-overlay.nix {
  # Below 3 are from release notes
  jetpackMajorMinorPatchVersion = "6.2";
  l4tMajorMinorPatchVersion = "36.4.3";
  cudaMajorMinorPatchVersion = "12.6.10";

  # nix build .#legacyPacakges.l4t-cuda.src; unpack the deb; find libnvidia-ptxjijtcompiler.so
  # and use that.
  cudaDriverMajorMinorVersion = "540.4.0";

  bspHash = "sha256-lJpEBJxM5qjv31cuoIIMh09u5dQco+STW58OONEYc9I=";
}
