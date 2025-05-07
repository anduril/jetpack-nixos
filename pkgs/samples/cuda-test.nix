{ cuda-samples, writeShellApplication }:
writeShellApplication {
  name = "cuda-test";
  text = ''
    BINARIES=(
      deviceQuery deviceQueryDrv bandwidthTest clock clock_nvrtc
      matrixMul matrixMulCUBLAS matrixMulDrv matrixMulDynlinkJIT
    )
    for binary in "''${BINARIES[@]}"; do
      real="$(find ${cuda-samples} -type f -name "$binary")"
      echo " * Running $real"
      # clock_nvrtc expects .cu files under $PWD/data
      pushd "$(dirname "$real")" && "$real" && popd
      echo
      echo
    done
  '';
}
