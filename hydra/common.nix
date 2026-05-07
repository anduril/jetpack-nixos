{
  # The platforms supported by the NixOS-CUDA Hydra instance
  supportedSystems ? [
    "x86_64-linux"
    "aarch64-linux"
  ]
, # The system evaluating this expression
  evalSystem ? builtins.currentSystem or "x86_64-linux"
, # Whether to apply hydraJob to each derivation.
  scrubJobs ? true
, # Whether to enable CUDA support.
  cudaSupport ? false
, # Specific CUDA capabilities to set.
  cudaCapabilities ? null
, # Additional overlays to apply to the package set.
  extraOverlays ? null
, # The path to Nixpkgs.
  nixpkgs ? null
,
}@args:
let
  # A self-reference to this flake to get overlays
  self = builtins.getFlake (builtins.toString ../.);

  # Default values won't make unsupplied arguments present; they just make the variable available in the scope.
  nixpkgs = args.nixpkgs or self.inputs.nixpkgs.outPath;

  lib = import (nixpkgs + "/lib");
in
{
  inherit lib;

  recursiveScrub =
    let
      shouldRecurse = x: lib.isAttrs x && !lib.isDerivation x && x.recurseForDerivations or false;
      scrubDrv = drv: lib.optionalAttrs (lib.isDerivation drv) (lib.hydraJob drv);
    in
    lib.mapAttrsRecursiveCond shouldRecurse (lib.const scrubDrv);

  recursiveScrubAndKeepEvaluatable =
    let
      shouldRecurse = x: lib.isAttrs x && !lib.isDerivation x && x.recurseForDerivations or false;
      canDeepEval = expr: (builtins.tryEval (builtins.deepSeq expr expr)).success;
      scrubDrv =
        drv:
        let
          scrubbed = lib.hydraJob drv;
        in
        lib.optionalAttrs (canDeepEval scrubbed) scrubbed;
    in
    lib.mapAttrsRecursiveCond shouldRecurse (lib.const scrubDrv);

  releaseLib = import (nixpkgs + "/pkgs/top-level/release-lib.nix") {
    inherit scrubJobs supportedSystems;
    system = evalSystem;
    packageSet = import nixpkgs;
    nixpkgsArgs = {
      # Allow filesets, despite using an older (and likely affected) version of Nix: https://github.com/NixOS/nix/issues/11503.
      __allowFileset = true;
      config = {
        # By default, Nixpkgs allows aliases. Setting them to false allows us to detect breakages sooner rather
        # than later.
        # TODO(@cbaker2): We cannot disallow aliases because they're used *everywhere*.
        allowAliases = true;
        allowUnfree = true;
        inherit cudaSupport;
        # Exclude cudaCapabilities if unset to allow selection of default capabilities.
        # TODO: How can we set cudaCapabilities per-system?
        ${if cudaCapabilities != null then "cudaCapabilities" else null} = cudaCapabilities;
        inHydra = true;
      };
      overlays = [ self.overlays.default ] ++ args.extraOverlays or [ ];
    };
  };
}
