# Generate arguments for instantiating the Nixpkgs that a JetPack NixOS
# configuration uses.
#
# Userspace depends on the JetPack major version and the SoC, which determines
# the GPU driver (openrm on Thor, nvgpu on Orin and Xavier) and the CUDA
# capability (see ./soc.nix). Everything else that depends on the SoM (kernel,
# device tree, firmware, flashing) is configured per machine by the module,
# outside of `pkgs`.
{ lib, overlay }:

{ majorVersion
, # The SoC userspace targets, e.g. "t234". null (a "generic" SoM) selects none.
  socType ? null
,
}:

let
  soc = import ./soc.nix { inherit lib; };

  jetpackVersions = [ "5" "6" "7" ];

  otherJetpacks = builtins.filter (v: v != majorVersion) jetpackVersions;

  selection = lib.optionalAttrs (socType != null) {
    inherit socType;
    inherit (soc.socs.${socType}) chipId gpuDriver;
  };

  selectJetpack =
    final: prev:
    let
      mkWarnJetpack =
        v:
        lib.warn "nvidia-jetpack${v} is unsupported when nixos is configured to use Jetpack ${majorVersion}" prev."nvidia-jetpack${v}";
    in
    {
      nvidia-jetpack = final."nvidia-jetpack${majorVersion}".overrideScope (_: _: selection);

      cudaPackages = final."cudaPackages_${lib.versions.major final."nvidia-jetpack${majorVersion}".cudaMajorMinorVersion}";
    }
    # Warn if anyone tries to evaluate non-default nvidia-jetpack package sets,
    # but keep them around to avoid missing attribute errors.
    // builtins.listToAttrs (map (v: { name = "nvidia-jetpack${v}"; value = mkWarnJetpack v; }) otherJetpacks);
in
{
  overlays = [
    overlay
    selectJetpack
  ];

  # CUDA support for the SoC. A package set without CUDA uses only `overlays`.
  config = {
    cudaCapabilities = soc.cudaCapabilitiesFor socType;
  };
}
