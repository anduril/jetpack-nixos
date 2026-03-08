{ armTrustedFirmware
, bspSrc
, buildPackages
, cpuBlPayloadDec
, hwKeyAgent
, lib
, nukeReferences
, nvLuksSrv
, optee-os
, opteeDtb
}:
let
  socType = armTrustedFirmware.socType;
in
lib.makeOverridable
  ({ earlyTaPaths }:
  let
    opteeOS = optee-os.overrideAttrs (finalAttrs: {
      earlyTaPaths = finalAttrs.earlyTaPaths or [ ] ++ earlyTaPaths;
    });

    teeRaw = "${opteeOS}/core/tee-raw.bin";
    dtb = "${opteeDtb}/tegra${lib.removePrefix "t" socType}-optee.dtb";

    image = buildPackages.runCommand "tos.img"
      {
        nativeBuildInputs = [ nukeReferences ];
        passthru = { inherit nvLuksSrv hwKeyAgent; };
      } ''
      mkdir -p $out
      ${buildPackages.python3}/bin/python3 ${bspSrc}/nv_tegra/tos-scripts/gen_tos_part_img.py \
        --monitor ${armTrustedFirmware}/bl31.bin \
        --os ${teeRaw} \
        --dtb ${dtb} \
        --tostype optee \
        $out/tos.img

      # Get rid of any string references to source(s)
      nuke-refs $out/*
    '';

    imageSpTool = buildPackages.runCommand "tos.img"
      {
        nativeBuildInputs = [ nukeReferences ];
        passthru = { inherit nvLuksSrv hwKeyAgent; };
      } ''
      # From public sources, see instructions in nvidia-jetson-optee-source.tbz2
      mkdir -p $out
      ${lib.getExe buildPackages.python3} ${armTrustedFirmware.src}/arm-trusted-firmware.${socType}/tools/sptool/sptool.py \
        -i ${teeRaw}:${dtb} \
        -o $out/tos.img

      cp ${armTrustedFirmware}/bl31.fip $out/

      nuke-refs $out/*
    '';
  in
  builtins.getAttr socType {
    t194 = image;
    t234 = image;
    t264 = imageSpTool;
  }
  )
{
  earlyTaPaths = lib.optionals (socType == "t194" || socType == "t234") [
    "${nvLuksSrv}/b83d14a8-7128-49df-9624-35f14f65ca6c.stripped.elf"
    "${cpuBlPayloadDec}/0e35e2c9-b329-4ad9-a2f5-8ca9bbbd7713.stripped.elf"
    "${hwKeyAgent}/82154947-c1bc-4bdf-b89d-04f93c0ea97c.stripped.elf"
  ];
}
