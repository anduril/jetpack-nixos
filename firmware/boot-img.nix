{ lib, pkgs, runCommand, cfg, jetpack, baseRcm, kernel, initrd, cmdline }:
let
  flash-tools = jetpack.l4tFlashTools;
  inherit (cfg.firmware.secureBoot) pkcFile;
  inherit (cfg.firmware.uefi.secureBoot) signer;
  # As mkRcmBootScript, before l4t_uefi_sign_image.sh.
  preSign = let cmds = cfg.firmware.secureBoot.preSignCommands pkgs; in
    lib.optionalString (pkcFile != null && cmds != "") "${cmds}\n";
  sign = image: mode: lib.optionalString (pkcFile != null) ''
    bash ${flash-tools}/l4t_uefi_sign_image.sh --image ${image} \
      --cert ${lib.escapeShellArg "${signer.cert}"} --key ${lib.escapeShellArg "${signer.key}"} --mode ${mode}
  '';
in
runCommand "boot-img-${cfg.name}-${jetpack.l4tMajorMinorPatchVersion}"
  cfg.firmware.secureBoot.derivationAttrs ''
  set -euo pipefail
  export PATH=${lib.makeBinPath flash-tools.flashDeps}:$PATH
  install -m 644 ${kernel} Image
  ${preSign + sign "Image" "nosplit"}
  cmdline=$(cat ${baseRcm}/bootimg/cmdline)
  CMDLINE=${lib.escapeShellArg cmdline}
  # flash.sh, verbatim: CMDLINE entries replace the base's same-key ones.
  if [ "''${CMDLINE}" != "" ]; then
  	for string in ''${CMDLINE}; do
  		lcl_str=$(echo $string | sed "s|\(.*\)=.*|\1|")
  		if [[ "''${cmdline}" =~ $lcl_str ]]; then
  			cmdline=$(echo "$cmdline" | sed "s|$lcl_str=[0-9a-zA-Z:/,]*||g")
  		fi
  		cmdline+="''${string} ";
  	done
  fi;
  ${flash-tools}/bootloader/mkbootimg --kernel Image --ramdisk ${initrd} --board "$(cat ${baseRcm}/bootimg/board)" \
    --output boot.img --cmdline "$cmdline"
  ${sign "boot.img" "append"}
  mkdir $out
  cp boot.img $out/
''
