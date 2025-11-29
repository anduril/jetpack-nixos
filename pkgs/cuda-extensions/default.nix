{ lib
,
}:
finalCudaPackages: prevCudaPackages:
let
  packages = lib.packagesFromDirectoryRecursive {
    inherit (finalCudaPackages) callPackage;
    directory = ./.;
  };

  jp = finalCudaPackages.pkgs.nvidia-jetpack;
in
{
  inherit (packages) vpi vpi-firmware;

  # A pattern emerges here:
  # We must inject the driver libraries needed by various packages upstream uses autoPatchelfIgnoreMissingDeps to
  # build, since consumers of these packages will see transitive symbol resolution failures.
  # If NVIDIA made stubs available, we could propagate those, but they don't for Jetson drivers.
  # When we add the missing driver libraries, we either set autoPatchelfIgnoreMissingDeps to the empty list or
  # filter out the names of the library we added, so missing libraries become failures.

  cuda_compat = prevCudaPackages.cuda_compat.overrideAttrs (prevAttrs: {
    buildInputs = prevAttrs.buildInputs or [ ] ++ [
      jp.l4t-core # libnvdla_runtime.so, libnvrm_gpu.so, and libnvrm_mem.so
    ];
    autoPatchelfIgnoreMissingDeps = [ ];
  });

  libcudla = prevCudaPackages.libcudla.overrideAttrs (prevAttrs: {
    buildInputs = prevAttrs.buildInputs or [ ] ++ [
      jp.l4t-cuda # libnvcudla.so
    ];
    autoPatchelfIgnoreMissingDeps = lib.filter
      (
        name: name != "libnvcudla.so"
      ) prevAttrs.autoPatchelfIgnoreMissingDeps or [ ];
  });

  # Inject the driver libraries needed for TensorRT's DLA functionality so transitive symbol resolution in consumers
  # of TensorRT don't fail (e.g., multimedia-samples). We only need to do this on Jetson devices with a DLA, so it is
  # sufficient to guard on the availability of libcudla, which is only available on Xavier and Orin.
  tensorrt =
    if !finalCudaPackages.libcudla.meta.available then
      prevCudaPackages.tensorrt
    else
      prevCudaPackages.tensorrt.overrideAttrs (prevAttrs: {
        buildInputs =
          prevAttrs.buildInputs or [ ]
          ++ (
            # Test if the standalone package for the libnvdla_compiler.so is available.
            # It may not exist or it may not be available, so use `or` to guard against missing attributes.
            if jp.l4t-dla-compiler.meta.available or false then
              [ jp.l4t-dla-compiler ]
            else if jp.l4t-core.meta.available or false then
              [ jp.l4t-core ]
            else
              [ ]
          );

        # Since we're explicitly including the library, we want autoPatchelf to fail if it can't find it.
        autoPatchelfIgnoreMissingDeps = lib.filter
          (
            name: name != "libnvdla_compiler.so"
          ) prevAttrs.autoPatchelfIgnoreMissingDeps or [ ];
      });
}
