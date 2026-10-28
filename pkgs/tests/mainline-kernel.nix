{ lib
, pkgs
, base
}:
let
  mainline = base.extendModules {
    modules = [{
      hardware.nvidia-jetpack.configureCuda = false;
      hardware.nvidia-jetpack.kernel.mainline = true;
    }];
  };
  overridden = mainline.extendModules {
    modules = [
      ({ pkgs, ... }: {
        boot.kernelPackages = pkgs.linuxPackages_6_12;
      })
    ];
  };
  customized = mainline.extendModules {
    modules = [
      ({ pkgs, ... }: {
        boot.kernelPackages = pkgs.linuxPackages_6_18.extend (_: prev: {
          kernel = prev.kernel.override {
            autoModules = false;
            ignoreConfigErrors = true;
            features.downstream = true;
          };
        });
        boot.kernelPatches = [{ name = "downstream"; patch = null; }];
      })
    ];
  };
  realtime = mainline.extendModules {
    modules = [{ hardware.nvidia-jetpack.kernel.realtime = true; }];
  };
  olderRealtime = overridden.extendModules {
    modules = [{ hardware.nvidia-jetpack.kernel.realtime = true; }];
  };
  disabled = mainline.extendModules {
    modules = [{ hardware.nvidia-jetpack.enable = lib.mkForce false; }];
  };
  tooOld = mainline.extendModules {
    modules = [ ({ pkgs, ... }: { boot.kernelPackages = pkgs.linuxPackages_6_6; }) ];
  };
  verify = system:
    let
      inherit (system) config;
      inherit (config.boot.kernelPackages) kernel;
      settings = kernel.configfile.structuredConfig;
      oot = lib.findFirst (p: (p.pname or "") == "l4t-oot-modules") null config.boot.extraModulePackages;
      patchNames = map (p: p.name) kernel.kernelPatches;
    in
    assert builtins.all (a: a.assertion) config.assertions;
    assert builtins.elem "jetpack-mainline" patchNames;
    assert builtins.elem "Hack-to-select-VIDEOBUF2_DMA_CONTIG" patchNames;
    assert oot.kernel.drvPath == kernel.drvPath;
    assert builtins.elem "kernel_name=nvmainline" oot.makeFlags;
    assert config.hardware.deviceTree.dtbSource.kernel.drvPath == kernel.drvPath;
    assert settings.EROFS_FS.tristate == "y";
    assert settings.EXFAT_FS.tristate == "y";
    assert settings.BLK_DEV_DM.tristate == "m";
    assert settings.DM_CRYPT.tristate == "m";
    assert settings.VIDEOBUF2_DMA_CONTIG.tristate == "m";
    true;
in
assert builtins.all verify [ mainline overridden customized realtime olderRealtime ];
assert mainline.options.boot.kernelPackages.highestPrio == 1000;
assert lib.versions.majorMinor mainline.config.boot.kernelPackages.kernel.version == "6.18";
assert lib.versions.majorMinor overridden.config.boot.kernelPackages.kernel.version == "6.12";
assert mainline.config.boot.kernelPackages.kernel.configfile.autoModules;
assert !mainline.config.boot.kernelPackages.kernel.configfile.ignoreConfigErrors;
assert !customized.config.boot.kernelPackages.kernel.configfile.autoModules;
assert customized.config.boot.kernelPackages.kernel.configfile.ignoreConfigErrors;
assert customized.config.boot.kernelPackages.kernel.features.downstream;
assert builtins.elem "downstream" (map (p: p.name) customized.config.boot.kernelPackages.kernel.kernelPatches);
assert realtime.config.boot.kernelPackages.kernel.configfile.structuredConfig.PREEMPT_RT.tristate == "y";
assert realtime.config.boot.kernelPackages.kernel.configfile.structuredConfig.PREEMPT.tristate == "y";
assert olderRealtime.config.boot.kernelPackages.kernel.configfile.structuredConfig.PREEMPT_RT.tristate == "y";
assert olderRealtime.config.boot.kernelPackages.kernel.configfile.structuredConfig.PREEMPT.tristate == "n";
assert disabled.config.boot.kernelPatches == [ ];
assert lib.any (a: !a.assertion && a.message == "hardware.nvidia-jetpack.kernel.mainline requires a kernel >= 6.9.") tooOld.config.assertions;
pkgs.runCommand "mainline-kernel-eval" { } ''
  touch $out
''
