# NOTE: Taken and refined from
# https://github.com/NixOS/nixpkgs/blob/3cc65eac1467c522aab0af30310f9f17d959e4c6/pkgs/development/cuda-modules/flags.nix
{ config
, cudaConfig
, cudaCapabilities ? (config.cudaCapabilities or [ ])
, cudaForwardCompat ? (config.cudaForwardCompat or true)
, cudaMajorMinorVersion
, lib
, stdenv
}:
let
  inherit (builtins) toJSON;
  inherit (cudaConfig.data) gpus;
  inherit (lib.asserts) assertMsg;
  inherit (lib.attrsets)
    attrNames
    attrValues
    dontRecurseIntoAttrs
    filterAttrs
    mapAttrs
    ;
  inherit (lib.lists)
    elem
    filter
    groupBy'
    intersectLists
    last
    map
    optionals
    unique
    ;
  inherit (lib.trivial) pipe throwIf;
  inherit (lib.strings) concatMapStringsSep concatStringsSep replaceStrings versionAtLeast;
  inherit (stdenv) hostPlatform;

  dropDots = replaceStrings [ "." ] [ "" ];

  mkCmakeCudaArchitecturesString = concatMapStringsSep ";" dropDots;

  mkGencodeFlag =
    targetKind: cudaCapability:
    let
      cap = dropDots cudaCapability;
    in
    "-gencode=arch=compute_${cap},code=${targetKind}_${cap}";

  mkRealArchitecture = cudaCapability: "sm_" + dropDots cudaCapability;

  mkVirtualArchitecture = cudaCapability: "compute_" + dropDots cudaCapability;

  /**
    Returns whether a GPU should be built by default for a particular CUDA version.

    # Type

    ```
    gpuIsDefault :: Version -> GpuInfo -> Bool
    ```
  */
  gpuIsDefault =
    cudaMajorMinorVersion:
    { dontDefaultAfterCudaMajorMinorVersion
    , isJetson
    , ...
    }:
    let
      recentGpu =
        dontDefaultAfterCudaMajorMinorVersion == null
        || versionAtLeast dontDefaultAfterCudaMajorMinorVersion cudaMajorMinorVersion;
    in
    recentGpu && !isJetson;

  /**
    Returns whether a GPU is supported for a particular CUDA version.

    # Type

    ```
    gpuIsSupported :: Version -> GpuInfo -> Bool
    ```
  */
  gpuIsSupported =
    cudaMajorMinorVersion:
    { minCudaMajorMinorVersion, maxCudaMajorMinorVersion, ... }:
    let
      lowerBoundSatisfied = versionAtLeast cudaMajorMinorVersion minCudaMajorMinorVersion;
      upperBoundSatisfied =
        (maxCudaMajorMinorVersion == null)
        || (versionAtLeast maxCudaMajorMinorVersion cudaMajorMinorVersion);
    in
    lowerBoundSatisfied && upperBoundSatisfied;

  # Flags are determined based on your CUDA toolkit by default.  You may benefit
  # from improved performance, reduced file size, or greater hardware support by
  # passing a configuration based on your specific GPU environment.
  #
  # cudaCapabilities :: List Capability
  # List of hardware generations to build.
  # E.g. [ "8.0" ]
  # Currently, the last item is considered the optional forward-compatibility arch,
  # but this may change in the future.
  #
  # cudaForwardCompat :: Bool
  # Whether to include the forward compatibility gencode (+PTX)
  # to support future GPU generations.
  # E.g. true
  #
  # Please see the accompanying documentation or https://github.com/NixOS/nixpkgs/pull/205351

  # supportedGpus :: List GpuInfo
  # GPUs which are supported by the provided CUDA version.
  supportedGpus = filter (gpuIsSupported cudaMajorMinorVersion) (attrValues gpus);

  # defaultGpus :: List GpuInfo
  # GPUs which are supported by the provided CUDA version and we want to build for by default.
  defaultGpus = filter (gpuIsDefault cudaMajorMinorVersion) supportedGpus;

  # supportedCapabilities :: List Capability
  supportedCapabilities = map (gpu: gpu.cudaCapability) supportedGpus;

  # defaultCapabilities :: List Capability
  # The default capabilities to target, if not overridden by the user.
  defaultCapabilities = map (gpu: gpu.cudaCapability) defaultGpus;

  # cudaArchNameToVersions :: AttrSet String (List String)
  # Maps the name of a GPU architecture to different versions of that architecture.
  # For example, "Ampere" maps to [ "8.0" "8.6" "8.7" ].
  cudaArchNameToVersions = groupBy' (versions: gpu: versions ++ [ gpu.cudaCapability ]) [ ]
    (
      gpu: gpu.archName
    )
    (attrValues gpus);

  # cudaCapabilityToName :: AttrSet String String
  # Maps the version of a GPU architecture to the name of that architecture.
  # For example, "8.0" maps to "Ampere".
  cudaCapabilityToName = mapAttrs (_: gpu: gpu.archName) gpus;

  # cudaCapabilityToIsJetson :: AttrSet String Boolean
  cudaCapabilityToIsJetson = mapAttrs (_: gpu: gpu.isJetson) gpus;

  # jetsonComputeCapabilities :: List String
  jetsonComputeCapabilities = pipe cudaCapabilityToIsJetson [
    (filterAttrs (_: isJetson: isJetson))
    attrNames
  ];

  # Find the intersection with the user-specified list of cudaCapabilities.
  # NOTE: Jetson devices are never built by default because they cannot be targeted along with
  # non-Jetson devices and require an aarch64 host platform. As such, if they're present anywhere,
  # they must be in the user-specified cudaCapabilities.
  # NOTE: We don't need to worry about mixes of Jetson and non-Jetson devices here -- there's
  # sanity-checking for all that in below.
  jetsonTargets = intersectLists jetsonComputeCapabilities cudaCapabilities;

  formatCapabilities =
    { cudaCapabilities
    , cudaForwardCompat ? true
    ,
    }:
    let
      # realArches :: List String
      # The real architectures are physical architectures supported by the CUDA version.
      # E.g. [ "sm_75" "sm_86" ]
      realArches = map mkRealArchitecture cudaCapabilities;

      # virtualArches :: List String
      # The virtual architectures are typically used for forward compatibility, when trying to support
      # an architecture newer than the CUDA version allows.
      # E.g. [ "compute_75" "compute_86" ]
      virtualArches = map mkVirtualArchitecture cudaCapabilities;

      # gencode :: List String
      # A list of CUDA gencode arguments to pass to NVCC.
      # E.g. [ "-gencode=arch=compute_75,code=sm_75" ... "-gencode=arch=compute_86,code=compute_86" ]
      gencode =
        let
          base = map (mkGencodeFlag "sm") cudaCapabilities;
          forward = mkGencodeFlag "compute" (last cudaCapabilities);
        in
        base ++ optionals cudaForwardCompat [ forward ];
    in
    {
      inherit
        cudaCapabilities
        cudaForwardCompat
        gencode
        realArches
        virtualArches
        ;

      # archNames :: List String
      # E.g. [ "Turing" "Ampere" ]
      #
      # Unknown architectures are rendered as sm_XX gencode flags.
      archNames = unique (
        map
          (
            cudaCapability: cudaCapabilityToName.${cudaCapability} or (mkRealArchitecture cudaCapability)
          )
          cudaCapabilities
      );

      # arches :: List String
      # By default, build for all supported architectures and forward compatibility via a virtual
      # architecture for the newest supported architecture.
      # E.g. [ "sm_75" "sm_86" "compute_86" ]
      arches = realArches ++ optionals cudaForwardCompat [ (last virtualArches) ];

      # gencodeString :: String
      # A space-separated string of CUDA gencode arguments to pass to NVCC.
      # E.g. "-gencode=arch=compute_75,code=sm_75 ... -gencode=arch=compute_86,code=compute_86"
      gencodeString = concatStringsSep " " gencode;

      # cmakeCudaArchitecturesString :: String
      # A semicolon-separated string of CUDA capabilities without dots, suitable for passing to CMake.
      # E.g. "75;86"
      cmakeCudaArchitecturesString = mkCmakeCudaArchitecturesString cudaCapabilities;

      # Jetson devices cannot be targeted by the same binaries which target non-Jetson devices. While
      # NVIDIA provides both `linux-aarch64` and `linux-sbsa` packages, which both target `aarch64`,
      # they are built with different settings and cannot be mixed.
      # isJetsonBuild :: Boolean
      isJetsonBuild =
        let
          requestedJetsonDevices = filter
            (
              cudaCapability: cudaCapabilityToIsJetson.${cudaCapability} or false
            )
            cudaCapabilities;
          requestedNonJetsonDevices = filter
            (
              cudaCapability: !(elem cudaCapability requestedJetsonDevices)
            )
            cudaCapabilities;
          jetsonBuildSufficientCondition = requestedJetsonDevices != [ ];
          jetsonBuildNecessaryCondition = requestedNonJetsonDevices == [ ] && hostPlatform.isAarch64;
        in
        throwIf (jetsonBuildSufficientCondition && !jetsonBuildNecessaryCondition) ''
          Jetson devices cannot be targeted with non-Jetson devices. Additionally, they require hostPlatform to be aarch64.
          You requested ${toJSON cudaCapabilities} for host platform ${hostPlatform.system}.
          Requested Jetson devices: ${toJSON requestedJetsonDevices}.
          Requested non-Jetson devices: ${toJSON requestedNonJetsonDevices}.
          Exactly one of the following must be true:
          - All CUDA capabilities belong to Jetson devices and hostPlatform is aarch64.
          - No CUDA capabilities belong to Jetson devices.
          See gpus.nix for a list of architectures supported by this version of Nixpkgs.
        ''
          jetsonBuildSufficientCondition
        && jetsonBuildNecessaryCondition;
    };
in
# Check Jetson-only
assert assertMsg
  (
    gpus ? "7.2" && gpus ? "8.7"
  ) "The following test requires both 7.2 and 8.7 be known GPUs";
assert
let
  expected = {
    cudaCapabilities = [
      "7.2"
      "8.7"
    ];
    cudaForwardCompat = true;

    archNames = [
      "Volta"
      "Ampere"
    ];
    realArches = [
      "sm_72"
      "sm_87"
    ];
    virtualArches = [
      "compute_72"
      "compute_87"
    ];
    arches = [
      "sm_72"
      "sm_87"
      "compute_87"
    ];

    gencode = [
      "-gencode=arch=compute_72,code=sm_72"
      "-gencode=arch=compute_87,code=sm_87"
      "-gencode=arch=compute_87,code=compute_87"
    ];
    gencodeString = "-gencode=arch=compute_72,code=sm_72 -gencode=arch=compute_87,code=sm_87 -gencode=arch=compute_87,code=compute_87";

    cmakeCudaArchitecturesString = "72;87";

    isJetsonBuild = true;
  };
  actual = formatCapabilities {
    cudaCapabilities = [
      "7.2"
      "8.7"
    ];
  };
  actualWrapped = (builtins.tryEval (builtins.deepSeq actual actual)).value;
in
assertMsg
  # We can't do this test unless we're targeting aarch64
  (hostPlatform.isAarch64 -> (expected == actualWrapped))
  ''
    Jetson devices can only be built with other Jetson devices.
    Both 7.2 and 8.7 are Jetson devices.
    Expected: ${builtins.toJSON expected}
    Actual: ${builtins.toJSON actualWrapped}
  '';
dontRecurseIntoAttrs
  {
    # formatCapabilities :: { cudaCapabilities: List Capability, cudaForwardCompat: Boolean } ->  { ... }
    inherit formatCapabilities;

    # cudaArchNameToVersions :: String => String
    inherit cudaArchNameToVersions;

    # cudaCapabilityToName :: String => String
    inherit cudaCapabilityToName;

    # dropDots :: String -> String
    inherit dropDots;

    # Aliases
    # TODO(@connorbaker): Deprecation warnings.
    dropDot = dropDots;

    inherit
      defaultCapabilities
      supportedCapabilities
      jetsonComputeCapabilities
      jetsonTargets
      ;
  }
  // formatCapabilities {
  inherit cudaForwardCompat;
  cudaCapabilities = if cudaCapabilities == [ ] then defaultCapabilities else cudaCapabilities;
}
