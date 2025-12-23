# https://docs.nvidia.com/jetson/archives/r36.4.4/DeveloperGuide/SD/TestPlanValidation.html#nvidia-containers
{ dockerTools
, fetchFromGitHub
, buildEnv
,
}:
let
  cuda-samples = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "cuda-samples";
    tag = "v12.5"; # There is no 12.6 tag
    hash = "sha256-LL9A6olrpSAqePumNzQbAdljnzhOehmqqOy5sJieJk8=";
  };

  extraPrefix = "/share";
in
dockerTools.buildImage {
  name = "l4t-jetpack-with-samples";

  fromImage = dockerTools.pullImage {
    imageName = "nvcr.io/nvidia/l4t-jetpack";
    os = "linux";
    arch = "arm64";
    imageDigest = "sha256:34ccf0f3b63c6da9eee45f2e79de9bf7fdf3beda9abfd72bbf285ae9d40bb673";
    finalImageTag = "r36.4.0";
    sha256 = "sha256-+5+GRmyCl2ZcdYIJHU5snuFzEx1QkZic9bhtx9ZjXeo=";
  };

  copyToRoot = [
    (buildEnv {
      name = "cuda-samples-fhs";
      paths = [ cuda-samples ];
      inherit extraPrefix;
    })
  ];

  config.Cmd = [ "bash" "-c" "make -C ${extraPrefix}/Samples/1_Utilities/deviceQuery && ${extraPrefix}/Samples/1_Utilities/deviceQuery/deviceQuery" ];
}
