{ l4t-multimedia
, upstreamLibv4l
}:

upstreamLibv4l.overrideAttrs (previousAttrs: {
  postInstall = (previousAttrs.postInstall or "") + ''
    rm "$out/lib/libv4l2.so.0.0.0"
    ln -s ${l4t-multimedia}/lib/libv4l2.so.0 "$out/lib/libv4l2.so.0.0.0"

    rm "$out/lib/libv4lconvert.so.0.0.0"
    ln -s ${l4t-multimedia}/lib/libv4lconvert.so.0 "$out/lib/libv4lconvert.so.0.0.0"
  '';
})
