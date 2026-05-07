builtins.mapAttrs
  (_: value: { ${value.config.nixpkgs.buildPlatform.system} = value.config.system.build.toplevel; })
  (builtins.getFlake (builtins.toString ../.)).nixosConfigurations
