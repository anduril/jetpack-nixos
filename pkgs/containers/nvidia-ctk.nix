{ buildGoModule, fetchFromGitHub, fetchpatch }:

buildGoModule rec {
  pname = "nvidia-ctk";
  version = "1.15.0-rc.4";

  # TODO(jared): pin to v1.15.0 once it is released
  # We currently rely on some features in an unreleased version of nvidia
  # container toolkit.
  src = fetchFromGitHub {
    owner = "nvidia";
    repo = "nvidia-container-toolkit";
    rev = "v${version}";
    hash = "sha256-Ky0mGothIq5BOAHc4ujrMrh1niBYUoSgaRnv30ymjsE=";
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

  ldflags = [ "-s" "-w" "-extldflags=-Wl,-z,lazy" ];

  meta.mainProgram = "nvidia-ctk";
}
