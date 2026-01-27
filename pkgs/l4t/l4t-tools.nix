{ bc
, buildFromDebs
, l4t-core
, lib
, makeWrapper
, stdenv
,
}:
# For tegrastats and jetson_clocks
buildFromDebs {
  pname = "nvidia-l4t-tools";
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ stdenv.cc.cc.lib l4t-core ];
  postPatch = ''
    # Remove a utility that bring in too many libraries
    rm -f bin/nv_macsec_wpa_supplicant bin/nv_wpa_supplicant_wifi bin/wpa_supplicant

    # This just contains a symlink to a binary already in /bin (nvcapture-status-decoder)
    rm -rf opt
  '';
  postFixup = ''
    wrapProgram $out/bin/nv_fuse_read.sh --prefix PATH : ${lib.makeBinPath [ bc ]}
  '';
}
