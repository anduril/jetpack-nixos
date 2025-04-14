# shellcheck shell=bash

# NOTE: Taken and refined from
# https://github.com/NixOS/nixpkgs/blob/3cc65eac1467c522aab0af30310f9f17d959e4c6/pkgs/development/cuda-modules/setup-hooks/setup-cuda-hook.sh
#
# Notable changes:
#
# - `CUDAToolkit_INCLUDE_DIR` is gone because it is unused
# - `CUDAToolkit_ROOT` is no longer passed explicitly because it is sourced from the environment
# - `CMAKE_POLICY_DEFAULT_CMP0074` is set to `NEW` by default to have CMake use the environment
# - To catch mistakes, select variable interpolations with empty variables will fail the build (using `:?`)

# Only run the hook from nativeBuildInputs
if ((${hostOffset:?} == -1 && ${targetOffset:?} == 0)); then
  echo "sourcing setup-cuda-hook.sh"
else
  return 0
fi

if (("${cudaSetupHookOnce:-0}" > 0)); then
  echo "skipping because the hook has been propagated more than once"
  return 0
fi

declare -ig cudaSetupHookOnce=1
declare -Ag cudaHostPathsSeen=()
declare -ag cudaForbiddenRPATHs=(
  # Compiler libraries
  "@unwrappedCCRoot@/lib"
  "@unwrappedCCRoot@/lib64"
  "@unwrappedCCRoot@/gcc/@hostPlatformConfig@/@ccVersion@"
  # Compiler library
  "@unwrappedCCLibRoot@/lib"
)

# NOTE: `appendToVar` does not export the variable to the environment because it is assumed to be a shell
# variable. To avoid variables being locally scoped, we must export it prior to adding values.
export NVCC_PREPEND_FLAGS="${NVCC_PREPEND_FLAGS:-}"
export NVCC_APPEND_FLAGS="${NVCC_APPEND_FLAGS:-}"

preConfigureHooks+=(setupCUDAPopulateArrays)
echo "added setupCUDAPopulateArrays to preConfigureHooks"

setupCUDAPopulateArrays() {
  # These names are all guaranteed to be arrays (though they may be empty), with or without __structuredAttrs set.
  # TODO: This function should record *where* it saw each CUDA marker so we can ensure the device offsets are correct.
  # Currently, it lumps them all into the same array, and we use that array to set environment variables.
  local -a dependencyArrayNames=(
    pkgsBuildBuild
    pkgsBuildHost
    pkgsBuildTarget
    pkgsHostHost
    pkgsHostTarget
    pkgsTargetTarget
  )

  for name in "${dependencyArrayNames[@]}"; do
    echo "searching dependencies in $name for CUDA markers"
    local -n deps="$name"
    for dep in "${deps[@]}"; do
      if [[ -f "$dep/nix-support/include-in-cudatoolkit-root" ]]; then
        echo "found CUDA marker in $dep from $name"
        cudaHostPathsSeen["$dep"]=1
      fi
    done
  done
}

preConfigureHooks+=(setupCUDAEnvironmentVariables)
echo "added setupCUDAEnvironmentVariables to preConfigureHooks"

setupCUDAEnvironmentVariables() {
  for path in "${!cudaHostPathsSeen[@]}"; do
    addToSearchPathWithCustomDelimiter ";" CUDAToolkit_ROOT "$path"
    echo "added $path to CUDAToolkit_ROOT"
  done

  # Set CUDAHOSTCXX if unset or null
  # https://cmake.org/cmake/help/latest/envvar/CUDAHOSTCXX.html
  if [[ -z ${CUDAHOSTCXX:-} ]]; then
    export CUDAHOSTCXX="@ccFullPath@"
    echo "set CUDAHOSTCXX to $CUDAHOSTCXX"
  fi

  # NOTE: CUDA 12.5 and later allow setting NVCC_CCBIN as a lower-precedent way of using -ccbin.
  # https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#compiler-bindir-directory-ccbin
  export NVCC_CCBIN="@ccFullPath@"
  echo "set NVCC_CCBIN to @ccFullPath@"

  # We append --compiler-bindir because NVCC uses the last --compiler-bindir it gets on the command line.
  # If users are able to be trusted to specify NVCC's host compiler, they can filter out this arg.
  # NOTE: Warnings of the form
  # nvcc warning : incompatible redefinition for option 'compiler-bindir', the last value of this option was used
  # indicate something in the build system is specifying `--compiler-bindir` (or `-ccbin`) and should be patched.
  appendToVar NVCC_APPEND_FLAGS "--compiler-bindir=@ccFullPath@"
  echo "appended --compiler-bindir=@ccFullPath@ to NVCC_APPEND_FLAGS"

  # NOTE: We set -Xfatbin=-compress-all, which reduces the size of the compiled
  #   binaries. If binaries grow over 2GB, they will fail to link. This is a problem for us, as
  #   the default set of CUDA capabilities we build can regularly cause this to occur (for
  #   example, with Magma).
  #
  # @SomeoneSerge: original comment was made by @ConnorBaker in .../cudatoolkit/common.nix
  if [[ -z ${cudaDontCompressFatbin:-} ]]; then
    appendToVar NVCC_PREPEND_FLAGS "-Xfatbin=-compress-all"
    echo "appended -Xfatbin=-compress-all to NVCC_PREPEND_FLAGS"
  fi
}

preConfigureHooks+=(setupCUDACmakeFlags)
echo "added setupCUDACmakeFlags to preConfigureHooks"

setupCUDACmakeFlags() {
  # If CMake is not present, don't set CMake flags.
  if ! command -v cmake &>/dev/null; then
    return 0
  fi

  # NOTE: Historically, we would set the following flags:
  # -DCUDA_HOST_COMPILER=@ccFullPath@
  # -DCMAKE_CUDA_HOST_COMPILER=@ccFullPath@
  # -DCUDAToolkit_ROOT=$CUDAToolkit_ROOT
  # However, as of CMake 3.13, if CUDAHOSTCXX is set, CMake will automatically use it as the host compiler for CUDA.
  # Since we set CUDAHOSTCXX in setupCUDAEnvironmentVariables, we don't need to set these flags anymore.
  # CUDAToolkit_ROOT is used as an environment variable, and specifying it manually overrides the environment variable.
  appendToVar cmakeFlags "-DCMAKE_POLICY_DEFAULT_CMP0074=NEW"
  echo "appended -DCMAKE_POLICY_DEFAULT_CMP0074=NEW to cmakeFlags"

  # Instruct CMake to ignore libraries provided by NVCC's host compiler when linking, as these should be supplied by
  # the stdenv's compiler.
  for forbiddenRPATH in "${cudaForbiddenRPATHs[@]}"; do
    addToSearchPathWithCustomDelimiter ";" CMAKE_CUDA_IMPLICIT_LINK_DIRECTORIES_EXCLUDE "$forbiddenRPATH"
    echo "appended $forbiddenRPATH to CMAKE_CUDA_IMPLICIT_LINK_DIRECTORIES_EXCLUDE"
  done
}

postFixupHooks+=(propagateCudaLibraries)
echo "added propagateCudaLibraries to postFixupHooks"

propagateCudaLibraries() {
  [[ -z ${cudaPropagateToOutput:-} ]] && return 0

  mkdir -p "${!cudaPropagateToOutput:?}/nix-support"
  # One'd expect this should be propagated-bulid-build-deps, but that doesn't seem to work
  printWords "@setupCudaHook@" >>"${!cudaPropagateToOutput:?}/nix-support/propagated-native-build-inputs"
  echo "added setupCudaHook to the propagatedNativeBuildInputs of output $cudaPropagateToOutput"

  local propagatedBuildInputs=("${!cudaHostPathsSeen[@]}")
  for output in $(getAllOutputNames); do
    if [[ $output != "$cudaPropagateToOutput" ]]; then
      propagatedBuildInputs+=("${!output:?}")
    fi
    break
  done

  # One'd expect this should be propagated-host-host-deps, but that doesn't seem to work
  printWords "${propagatedBuildInputs[@]}" >>"${!cudaPropagateToOutput:?}/nix-support/propagated-build-inputs"
  echo "added ${propagatedBuildInputs[*]} to the propagatedBuildInputs of output $cudaPropagateToOutput"
}
