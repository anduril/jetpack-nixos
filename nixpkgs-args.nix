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
      # The real package sets, saved the first time these overlays are applied.
      # If they are applied again for another JetPack version (the module
      # appends them to a `nixpkgs.pkgs` that `lib.nixpkgsArgsFor` already made
      # for a different `majorVersion`), the sets replaced below are found here.
      scopes = prev._jetpackNixosScopes or (lib.genAttrs (map (v: "nvidia-jetpack${v}") jetpackVersions) (name: prev.${name}));

      # A package set for another JetPack major version must not end up in a
      # closure for this one, so referencing any of its attributes is an error.
      # The attribute names are kept, so `?` still works without throwing, and
      # `recurseForDerivations` is false, so tools that walk the package set
      # (`nix-env -qa`, `nix search`, Hydra's `packagePlatforms`) skip it.
      mkUnsupportedJetpack =
        v:
        lib.mapAttrs
          (name: _: throw ''
            `nvidia-jetpack${v}.${name}` was referenced, but this package set is for JetPack ${majorVersion}.
            Use `nvidia-jetpack` (JetPack ${majorVersion}) instead, or, if your SoM supports it, switch to
            JetPack ${v} by setting `hardware.nvidia-jetpack.majorVersion = "${v}"` (or passing
            `majorVersion = "${v}"` to jetpack-nixos's `lib.nixpkgsArgsFor`).
          '')
          scopes."nvidia-jetpack${v}"
        // { recurseForDerivations = false; };
    in
    {
      _jetpackNixosScopes = scopes;

      "nvidia-jetpack${majorVersion}" = scopes."nvidia-jetpack${majorVersion}";

      nvidia-jetpack = final."nvidia-jetpack${majorVersion}".overrideScope (_: _: selection);

      cudaPackages = final."cudaPackages_${lib.versions.major final."nvidia-jetpack${majorVersion}".cudaMajorMinorVersion}";
    }
    // builtins.listToAttrs (map (v: { name = "nvidia-jetpack${v}"; value = mkUnsupportedJetpack v; }) otherJetpacks);
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
