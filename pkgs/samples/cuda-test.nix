{ cuda-samples, writeShellApplication }:
writeShellApplication {
  name = "cuda-test";
  text = ''
    BINARIES=(
      deviceQuery deviceQueryDrv bandwidthTest clock clock_nvrtc
      matrixMul matrixMulCUBLAS matrixMulDrv matrixMulDynlinkJIT
    )
    # clock_nvrtc expects .cu files under $PWD/data
    cd ${cuda-samples}/bin
    for binary in "''${BINARIES[@]}"; do
      echo " * Running $binary"
      ./"$binary"
      echo
      echo
    done
  '';
}
