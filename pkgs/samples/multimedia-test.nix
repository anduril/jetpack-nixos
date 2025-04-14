{ multimedia-samples, writeShellApplication }:
# ./result/bin/video_decode H264 /nix/store/zry377bb5vkz560ra31ds8r485jsizip-multimedia-samples-35.1.0-20220825113828/data/Video/sample_outdoor_car_1080p_10fps.h26
# (Requires X11)
#
# Doing example here: https://docs.nvidia.com/jetson/l4t-multimedia/l4t_mm_07_video_convert.html
writeShellApplication {
  name = "multimedia-test";
  text = ''
    WORKDIR=$(mktemp -d)
    on_exit() {
      rm -rf "$WORKDIR"
    }
    trap on_exit EXIT

    echo " * Running jpeg_decode"
    ${multimedia-samples}/bin/jpeg_decode num_files 1 ${multimedia-samples}/data/Picture/nvidia-logo.jpg "$WORKDIR"/nvidia-logo.yuv
    echo
    echo " * Running video_decode"
    ${multimedia-samples}/bin/video_decode H264 --disable-rendering ${multimedia-samples}/data/Video/sample_outdoor_car_1080p_10fps.h264
    echo
    echo " * Running video_cuda_enc"
    if ! grep -q -E "p3767-000[345]" /proc/device-tree/compatible; then
      ${multimedia-samples}/bin/video_cuda_enc ${multimedia-samples}/data/Video/sample_outdoor_car_1080p_10fps.h264 1920 1080 H264 "$WORKDIR"/test.h264
    else
      echo "Orin Nano does not support hardware video encoding--skipping test"
    fi
    echo
    echo " * Running video_convert"
    ${multimedia-samples}/bin/video_convert "$WORKDIR"/nvidia-logo.yuv 1920 1080 YUV420 "$WORKDIR"/test.yuv 1920 1080 YUYV
    echo
  '';
}
