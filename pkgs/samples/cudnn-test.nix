{ cudnn-samples, writeShellApplication }:
writeShellApplication {
  name = "cudnn-test";
  text = ''
    echo " * Running conv_sample"
    ${cudnn-samples}/bin/conv_sample
  '';
}
