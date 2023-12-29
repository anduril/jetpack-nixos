{ fetchFromGitLab, buildGoModule, fetchpatch }:

buildGoModule rec {
  pname = "nvidia-ctk";
  version = "unstable-${builtins.substring 0 7 src.rev}";

  # TODO(jared): pin to v1.15.0 once it is released
  # We currently rely on some features in an unreleased version of nvidia
  # container toolkit.
  src = fetchFromGitLab {
    owner = "nvidia";
    repo = "container-toolkit/container-toolkit";
    rev = "a2262d00cc6d98ac2e95ae2f439e699a7d64dc17";
    hash = "sha256-Oi04PIES0qTih/EiFBStIoBadM3H52+81KEfUumQcIs=";
  };

  patches = [
    # ensure nvidia-ctk can build with Go versions less than 1.20 (currently
    # required on their latest release)
    (fetchpatch {
      name = "Fix-double-error-wrap-fmt";
      url = "https://gitlab.com/nvidia/container-toolkit/container-toolkit/-/commit/80756d00a6b75761103c50f605cece5fa7e39392.patch";
      hash = "sha256-hoeMUUPWKToCR7V/JG26wF6SCoHQwQORcGimH6EXDJ8=";
    })
    (fetchpatch {
      name = "Use-golang-1.17";
      url = "https://gitlab.com/nvidia/container-toolkit/container-toolkit/-/commit/5956b04096d1a92b241b13cc1f3e208f8b99eea0.patch";
      hash = "sha256-VB3+ijc2Pdlm1W2LqvCjx9KDYKinWBkr/eiUJEwig/o=";
    })
    (fetchpatch {
      name = "Draft-Compat-with-golang-1.17";
      url = "https://gitlab.com/nvidia/container-toolkit/container-toolkit/-/commit/86f68a49014a4cffb7dcb51f14a02f6f1816b2ee.patch";
      hash = "sha256-ioWstYky7LbIGtlfMMlbhIVN8yH7Qgp3z4wrkytT3TY=";
    })
    # ensure nvidia-ctk can find ldconfig
    ./nixos-ldconfig.patch
  ];

  subPackages = [ "cmd/nvidia-ctk" ];

  vendorHash = null;

  ldflags = [ "-s" "-w" "-extldflags=-Wl,-z,lazy" ];
}
