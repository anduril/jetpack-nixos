{ autoAddDriverRunpath
, cudaPackages
, debs
, dpkg
, pkg-config
, stdenv
}:
# This package is unfortunately not identical to the upstream cuda-samples
# published at https://github.com/NVIDIA/cuda-samples, so we can't use
# nixpkgs's pkgs/tests/cuda packages
stdenv.mkDerivation {
  pname = "cuda-samples";
  version = debs.common."cuda-samples-${cudaPackages.cudaVersionDashes}".version;
  src = debs.common."cuda-samples-${cudaPackages.cudaVersionDashes}".src;

  unpackCmd = "dpkg -x $src source";
  sourceRoot = "source/usr/local/cuda-${cudaPackages.cudaVersion}/samples";

  patches = [ ./cuda-samples.patch ];

  nativeBuildInputs = [ dpkg pkg-config autoAddDriverRunpath ];
  buildInputs = [ cudaPackages.cudatoolkit ];

  preConfigure = ''
    export CUDA_PATH=${cudaPackages.cudatoolkit}
    export CUDA_SEARCH_PATH=${cudaPackages.cudatoolkit}/lib/stubs
  '';

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 -t $out/bin bin/${stdenv.hostPlatform.parsed.cpu.name}/${stdenv.hostPlatform.parsed.kernel.name}/release/*

    # *_nvrtc samples require your current working directory contains the corresponding .cu file
    find -ipath "*_nvrtc/*.cu" -exec install -Dt $out/data {} \;

    runHook postInstall
  '';
}
