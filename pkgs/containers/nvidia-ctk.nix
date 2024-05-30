{ buildGoModule, fetchFromGitHub, fetchpatch }:

let
  # From https://gitlab.com/nvidia/container-toolkit/container-toolkit/-/blob/03cbf9c6cd26c75afef8a2dd68e0306aace80401/Makefile#L54
  cliVersionPackage = "github.com/NVIDIA/nvidia-container-toolkit/internal/info";
in
buildGoModule rec {
  pname = "nvidia-ctk";
  version = "1.15.0";

  src = fetchFromGitHub {
    owner = "nvidia";
    repo = "nvidia-container-toolkit";
    rev = "v${version}";
    hash = "sha256-LOglihWESq9Ha+e8yvKBQwiy+v/dxNRxImKuKxPuw/8=";
  };

  patches = [
    # ensure nvidia-ctk can build with Go versions less than 1.20 (currently
    # required on their latest release)
    (fetchpatch {
      name = "Add-errors-Join-wrapper";
      url = "https://github.com/NVIDIA/nvidia-container-toolkit/commit/92f17e94939bf8c213419749f5f7b48d2f0e618c.patch";
      hash = "sha256-ioWstYky7LbIGtlfMMlbhIVN8yH7Qgp3z4wrkytT3TY=";
    })
    (fetchpatch {
      name = "Fix-double-error-wrap-fmt";
      url = "https://github.com/NVIDIA/nvidia-container-toolkit/commit/f23fd2ce38ee3a9e87ac41c265b637cf97990ac7.patch";
      hash = "sha256-hoeMUUPWKToCR7V/JG26wF6SCoHQwQORcGimH6EXDJ8=";
    })
  ];

  subPackages = [ "cmd/nvidia-ctk" ];

  vendorHash = null;


  ldflags = [
    "-s"
    "-w"
    "-extldflags=-Wl,-z,lazy"
    "-X"
    "${cliVersionPackage}.version=${version}"
  ];

  meta.mainProgram = "nvidia-ctk";
}
