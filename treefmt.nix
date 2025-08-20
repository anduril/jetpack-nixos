pkgs:
pkgs.treefmt.withConfig {
  settings = {
    tree-root-file = "flake.nix";
    on-unmatched = "warn";
    excludes = [
      "*.lock"

      # diff files
      "*.mbox"
      "*.patch"
      "*.diff"

      # VCS files
      ".gitignore"
      ".git-blame-ignore-revs"

      # misc
      "LICENSE"
      "*.md"
      "*.dts"
    ];

    formatter.nixfmt = {
      command = "nixpkgs-fmt";
      includes = [ "*.nix" ];
    };

    formatter.shfmt = {
      command = "shfmt";
      options = [ "-w" "-i" "2" ];
      includes = [
        "*.sh"
        "pkgs/jetson-benchmarks/scripts/*"
      ];
    };

    formatter.black = {
      command = "black";
      includes = [ "*.py" ];
    };

    formatter.yamlfmt = {
      command = "yamlfmt";
      includes = [ "*.yml" "*.yaml" ];
    };

    formatter.jsonfmt = {
      command = "jsonfmt";
      options = [ "-w" ];
      includes = [ "*.json" ];
    };
  };

  runtimeInputs = [ pkgs.nixpkgs-fmt pkgs.shfmt pkgs.black pkgs.yamlfmt pkgs.jsonfmt ];
}
