{ vpi2-samples, writeShellApplication }:
# Tested via "./result/bin/vpi_sample_05_benchmark <cpu|pva|cuda>" (Try pva especially)
# Getting a bunch of "pva 16000000.pva0: failed to get firmware" messages, so unsure if its working.
writeShellApplication {
  name = "vpi2-test";
  text = ''
    echo " * Running vpi_sample_05_benchmark cuda"
    ${vpi2-samples}/bin/vpi_sample_05_benchmark cuda
    echo

    echo " * Running vpi_sample_05_benchmark cpu"
    ${vpi2-samples}/bin/vpi_sample_05_benchmark cpu
    echo

    CHIP="$(tr -d '\0' < /proc/device-tree/compatible)"
    if [[ "''${CHIP}" =~ "tegra194" ]]; then
      echo " * Running vpi_sample_05_benchmark pva"
      ${vpi2-samples}/bin/vpi_sample_05_benchmark pva
      echo
    fi
  '';
  # PVA is only available on Xaviers. If the Jetpack version of the
  # firmware doesnt match the vpi2 version, it might fail with the
  # following:
  # [  435.318277] pva 16800000.pva1: invalid symbol id in descriptor for dst2 VMEM
  # [  435.318467] pva 16800000.pva1: failed to map DMA desc info
}
