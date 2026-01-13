{ cuda-test
, cudnn-test
, cupti-test
, cudaPackages
, lib
, multimedia-test
, vpi-test
, writeShellApplication
}:
writeShellApplication {
  name = "combined-test";
  text = ''
    echo "====="
    echo "Running CUDA test"
    echo "====="
    ${cuda-test}/bin/cuda-test

    echo "====="
    echo "Running CUDNN test"
    echo "====="
    ${cudnn-test}/bin/cudnn-test

    echo "====="
    echo "Running CUPTI test"
    echo "====="
    ${cupti-test}/bin/cupti-test

    echo "====="
    echo "Running TensorRT test"
    echo "====="
    ${lib.getExe cudaPackages.tensorrt-samples.passthru.testers.sample_onnx_mnist.default}

    echo "====="
    echo "Running Multimedia test"
    echo "====="
    ${multimedia-test}/bin/multimedia-test

    echo "====="
    echo "Running VPI test"
    echo "====="
    ${vpi-test}/bin/vpi-test
  '';
}
