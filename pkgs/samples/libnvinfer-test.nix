{ libnvinfer-samples, writeShellApplication }:
writeShellApplication {
  name = "libnvinfer-test";
  text = ''
    echo " * Running sample_onnx_mnist"
    ${libnvinfer-samples}/bin/sample_onnx_mnist --datadir ${libnvinfer-samples}/data/mnist
    echo
    echo
  '';
}
