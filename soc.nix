# Facts about the Jetson SoCs, kept in one place for the overlay, the NixOS
# modules, and the per-machine firmware package set.
{ lib }:

let
  socs = {
    t194 = {
      # Xavier
      family = "t19x";
      chipId = "0x19";
      pkcListChipId = null;
      gpuDriver = "nvgpu";
      cudaCapability = "7.2";
    };

    t234 = {
      # Orin
      family = "t23x";
      chipId = "0x23";
      pkcListChipId = null;
      gpuDriver = "nvgpu";
      cudaCapability = "8.7";
    };

    t264 = {
      # Thor
      family = "t26x";
      chipId = "0x26";
      pkcListChipId = "0x260";
      gpuDriver = "openrm";
      cudaCapability = "11.0";
    };
  };

  isXavier = lib.hasPrefix "xavier-";
  isOrin = lib.hasPrefix "orin-";
  isThor = lib.hasPrefix "thor-";

  # The SoC of a `hardware.nvidia-jetpack.som`; null for "generic".
  socTypeForSom =
    som:
    if som == null || som == "generic" then null
    else if isThor som then "t264"
    else if isOrin som then "t234"
    else if isXavier som then "t194"
    else throw "Unknown SoC type for SoM \"${som}\"";

  # The GPU driver userspace of a SoC. null (a "generic" SoM) keeps the package
  # set's default, nvgpu.
  gpuDriverFor = socType: if socType == null then null else socs.${socType}.gpuDriver;

  # The CUDA capabilities a package set for a SoC targets. null (a "generic"
  # SoM) targets both SoCs that JetPack 5 and 6 support.
  cudaCapabilitiesFor =
    socType:
    if socType == null then [ socs.t194.cudaCapability socs.t234.cudaCapability ]
    else [ socs.${socType}.cudaCapability ];
in
{
  inherit socs socTypeForSom gpuDriverFor cudaCapabilitiesFor;

  gpuDriverForSom = som: gpuDriverFor (socTypeForSom som);

  # The CUDA capabilities a configuration with this SoM targets.
  cudaCapabilitiesForSom = som: cudaCapabilitiesFor (socTypeForSom som);
}
