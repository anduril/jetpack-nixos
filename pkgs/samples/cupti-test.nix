{ cupti-samples, writeShellApplication }:
# NOTE: Must run as root:
# auto_range_profiling.cu:336: error: function cuptiProfilerInitialize(&profilerInitializeParams) failed with error
# CUPTI_ERROR_INSUFFICIENT_PRIVILEGES.
writeShellApplication {
  name = "cupti-test";
  text = ''
    # Not entirely sure which utilities are relevant here, I'll just pick a few
    # See: https://docs.nvidia.com/cupti/main/main.html?highlight=samples#samples
    #
    for binary in auto_range_profiling callback_timestamp pc_sampling; do
      echo " * Running $binary"
      ${cupti-samples}/bin/"$binary"
      echo
      echo
    done

    # cupti_query fails on Orin with the following message:
    # "Error CUPTI_ERROR_LEGACY_PROFILER_NOT_SUPPORTED for CUPTI API function 'cuptiDeviceEnumEventDomains'."
    #
    # https://forums.developer.nvidia.com/t/whether-cuda-supports-gpu-devices-with-8-6-compute-capability/274884/4
    # Orin doesn't support the "legacy profile"
    if ! grep -q -E "tegra234" /proc/device-tree/compatible; then
      echo " * Running cupti_query"
      ${cupti-samples}/bin/cupti_query
      echo
      echo
    fi
  '';
}
