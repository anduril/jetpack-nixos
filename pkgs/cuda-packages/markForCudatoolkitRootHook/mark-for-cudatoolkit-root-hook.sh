# shellcheck shell=bash

# NOTE: Taken and refined from
# https://github.com/NixOS/nixpkgs/blob/3cc65eac1467c522aab0af30310f9f17d959e4c6/pkgs/development/cuda-modules/setup-hooks/mark-for-cudatoolkit-root-hook.sh

# Only run the hook from nativeBuildInputs
if ((${hostOffset:?} == -1 && ${targetOffset:?} == 0)); then
  echo "sourcing mark-for-cudatoolkit-root-hook.sh"
else
  return 0
fi

fixupOutputHooks+=(markForCUDAToolkit_ROOT)
echo "added markForCUDAToolkit_ROOT to fixupOutputHooks"

markForCUDAToolkit_ROOT() {
  mkdir -p "${prefix:?}/nix-support"
  local -r markerFile="include-in-cudatoolkit-root"
  local -r markerPath="$prefix/nix-support/$markerFile"

  # Return early if the file already exists.
  if [[ -f $markerPath ]]; then
    return 0
  fi

  echo "marking output ${output:?} for inclusion by setupCudaHook"
  touch "$markerPath"
}
