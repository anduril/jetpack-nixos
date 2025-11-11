{ lib
, self
, l4tAtLeast
, l4tOlder
}:
let
  packages = lib.packagesFromDirectoryRecursive {
    inherit (self) callPackage;
    directory = ./.;
  };
in
{
  inherit (packages)
    ### Debs from L4T BSP
    l4t-3d-core
    l4t-camera
    l4t-core
    l4t-cuda
    l4t-cupva
    l4t-firmware
    l4t-gbm
    l4t-gstreamer
    l4t-init
    l4t-multimedia
    l4t-nvfancontrol
    l4t-nvpmodel
    l4t-nvsci
    l4t-pva
    l4t-tools
    l4t-wayland;
} // lib.optionalAttrs (l4tAtLeast "36") {
  inherit (packages)
    l4t-dla-compiler
    l4t-nvml
    ;
  nvidia-smi = packages.l4t-nvml;
} // lib.optionalAttrs (l4tOlder "38") {
  inherit (packages) l4t-xusb-firmware; # L4T 38+ uses upstream firmware
} // lib.optionalAttrs (l4tAtLeast "38") {
  inherit (packages) l4t-bootloader-utils;
}
