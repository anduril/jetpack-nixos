{ bspSrc, runCommand }:

runCommand "nv_tcu_demuxer" { }
  ''
    install -Dm0755 ${bspSrc}/tools/demuxer/nv_tcu_demuxer $out/bin/nv_tcu_demuxer
  ''
