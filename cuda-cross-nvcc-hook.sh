# shellcheck shell=bash

(("$hostOffset" == -1 && "$targetOffset" == 0)) || return 0

if [[ -z ${CUDACXX-} ]]; then
  export CUDACXX="@out@/bin/nvcc"
fi

if [[ -z ${CUDA_NVCC_EXECUTABLE-} ]]; then
  export CUDA_NVCC_EXECUTABLE="@out@/bin/nvcc"
fi

addCudaHostPathsToFindCudaSearchPaths() {
  declare -p cudaHostPathsSeen &>/dev/null || return 0

  local cudaHostPath
  for cudaHostPath in "${!cudaHostPathsSeen[@]}"; do
    if [[ -d $cudaHostPath/include ]]; then
      addToSearchPath CUDA_INC_PATH "$cudaHostPath/include"
    fi
    if [[ -d $cudaHostPath/lib ]]; then
      addToSearchPath CUDA_LIB_PATH "$cudaHostPath/lib"
    fi
  done
  export CUDA_INC_PATH CUDA_LIB_PATH

  prependToVar cmakeFlags "-DCUDA_TOOLKIT_ROOT_DIR=@targetCudaNvcc@"
}
preConfigureHooks+=(addCudaHostPathsToFindCudaSearchPaths)
