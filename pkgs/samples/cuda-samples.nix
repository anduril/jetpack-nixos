{ cudaPackages
, lib
}:
lib.warnOnInstantiate "nvidia-jetpack.samples.cuda-samples has been renamed to cudaPackages.cuda-samples" cudaPackages.cuda-samples
