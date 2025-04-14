{ cuda-test
, cudnn-test
, cupti-test
, libnvinfer-test
, multimedia-test
, vpi2-test
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
    ${libnvinfer-test}/bin/libnvinfer-test

    echo "====="
    echo "Running Multimedia test"
    echo "====="
    ${multimedia-test}/bin/multimedia-test

    echo "====="
    echo "Running VPI2 test"
    echo "====="
    ${vpi2-test}/bin/vpi2-test
  '';
}
