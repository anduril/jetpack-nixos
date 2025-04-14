{ backendStdenv
, cuda_cccl
, cuda_cudart
, cuda_cuobjdump
, cuda_cupti
, cuda_cuxxfilt
, cuda_gdb
, cuda_nvcc
, cuda_nvdisasm
, cuda_nvml_dev
, cuda_nvprune
, cuda_nvrtc
, cuda_nvtx
, cuda_profiler_api
, cuda_sanitizer_api
, cudaMajorMinorPatchVersion
, lib
, libcublas
, libcufft
, libcurand
, libcusolver
, libcusparse
, libnpp
, symlinkJoin
,
}:

let
  inherit (lib.attrsets) getLib;
  inherit (lib.lists) concatMap filter map;
  inherit (lib.trivial) pipe;
  getAllOutputs = p: p.all or p;
  hostPackages = filter (p: p != null) [
    cuda_cuobjdump
    cuda_gdb
    cuda_nvcc
    cuda_nvdisasm
    cuda_nvprune
  ];
  targetPackages = filter (p: p != null) [
    cuda_cccl
    cuda_cudart
    cuda_cupti
    cuda_cuxxfilt
    cuda_nvml_dev
    cuda_nvrtc
    cuda_nvtx
    cuda_profiler_api
    cuda_sanitizer_api
    libcublas
    libcufft
    libcurand
    libcusolver
    libcusparse
    libnpp
  ];

  # This assumes we put `cudatoolkit` in `buildInputs` instead of `nativeBuildInputs`:
  allPackages = pipe hostPackages [
    (map (p: p.__spliced.buildHost or p))
    (hostPackages: hostPackages ++ targetPackages)
  ];
in
symlinkJoin {
  pname = "cudatoolkit";
  version = cudaMajorMinorPatchVersion;
  paths = concatMap getAllOutputs allPackages;

  passthru = {
    lib = symlinkJoin {
      name = "cudatoolkit-lib-${cudaMajorMinorPatchVersion}";
      version = cudaMajorMinorPatchVersion;
      paths = map getLib allPackages;
    };

    # TODO(@connorbaker): Deprecation warnings.
    cc = backendStdenv.cc;
  };

  meta = with lib; {
    description = "Wrapper substituting the deprecated runfile-based CUDA installation";
    license = licenses.nvidiaCuda;
    platforms = [ "aarch64-linux" ];
  };
}
