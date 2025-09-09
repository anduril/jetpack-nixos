{ lib
, pkgs
, runCommand
, cfg
, flash-tools
, mkFlashScript
, mkFlashScriptArgs ? { }
}:

let
  variant =
    if builtins.length cfg.firmware.variants != 1
    then throw "mkFlashCmdScript requires exactly one Jetson variant set in hardware.nvidia-jetson.firmware.variants"
    else builtins.elemAt cfg.firmware.variants 0;
in
runCommand "flash-tools-flashcmd"
{
  # Needed for signing
  inherit (cfg.firmware.secureBoot) requiredSystemFeatures;
} ''
  export BOARDID=${variant.boardid}
  export BOARDSKU=${variant.boardsku}
  export FAB=${variant.fab}
  export BOARDREV=${variant.boardrev}
  ${lib.optionalString (variant.chipsku != null) ''
  export CHIP_SKU=${variant.chipsku}
  ''}
  export CHIPREV=${variant.chiprev}
  ${lib.optionalString (variant.ramcode != null) ''
  export RAMCODE=${variant.ramcode}
  ''}

  ${cfg.firmware.secureBoot.preSignCommands pkgs}

  ${mkFlashScript flash-tools (mkFlashScriptArgs // { flashArgs = [ "--no-root-check" "--no-flash" ] ++ (mkFlashScriptArgs.flashArgs or cfg.flashScriptOverrides.flashArgs); }) }

  cp -r ./ $out
''
