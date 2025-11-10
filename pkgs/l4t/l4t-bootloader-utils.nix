{ buildFromDebs
, l4t-core
, stdenv
,
}:
buildFromDebs {
  pname = "nvidia-l4t-bootloader-utils";
  buildInputs = [ stdenv.cc.cc.lib l4t-core ];
  postPatch = ''
    # Remove NVIDIA utilities for which we have a NixOS specific implementation
    rm -f bin/nv_bootloader_capsule_updater.sh bin/nv_bootloader_payload_updater

    # Remove fwupd and systemd stuff
    rm -rf etc
  '';
}
