{ cudnn-samples, writeShellApplication }:
# NOTE: `RNN` produces a `result.txt` which needs to be removed if we were to include that test.
# NOTE: `multiHeadAttention` requires arguments to run.
writeShellApplication {
  name = "cudnn-test";
  text = ''
    echo " * Running conv_sample"
    ${cudnn-samples}/bin/conv_sample
  '';
}
