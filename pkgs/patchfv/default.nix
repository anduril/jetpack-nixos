{ writers
, python3Packages
,
}:

writers.writePython3Bin "patchfv"
{
  libraries = [ python3Packages.uefi-firmware-parser ];
  # E501: ignore line length
  flakeIgnore = [ "E501" ];
}
  (builtins.readFile ./patchfv.py)
