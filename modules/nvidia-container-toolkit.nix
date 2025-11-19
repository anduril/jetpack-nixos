{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkDefault
    mkForce
    mkIf
    mkMerge
    mkRenamedOptionModule
    ;

  cfg = config.hardware.nvidia-jetpack;
in
{
  imports = [
    (mkRenamedOptionModule [ "hardware" "nvidia-jetpack" "container-toolkit" "enable" ] [ "hardware" "nvidia-container-toolkit" "enable" ])
  ];

  config = mkIf cfg.enable (mkMerge [
    {
      hardware.nvidia-container-toolkit.enable = mkDefault (
        with config.virtualisation; docker.enable && docker.enableNvidia || podman.enable && podman.enableNvidia
      );
    }
    (mkIf config.hardware.nvidia-container-toolkit.enable {
      systemd.services.nvidia-container-toolkit-cdi-generator = {
        # TODO: Upstream waits on `system-udev-settle.service`:
        # https://github.com/NixOS/nixpkgs/blob/ce01daebf8489ba97bd1609d185ea276efdeb121/nixos/modules/services/hardware/nvidia-container-toolkit/default.nix#L240
        # That's not recommended; instead we should have udev rules for the devices we care about so we can wait on them specifically.
        wants = [ "modprobe@nvgpu.service" ];
        after = [ "modprobe@nvgpu.service" ];

        # TODO: A previous version of this service included the following note:
        #
        #  # Wait until all devices are present before generating CDI
        #  # configuration. Also ensure that we aren't passing any directories
        #  # or glob patterns to udevadm (Jetpack 6 CSVs seem to add these,
        #  # though the Jetpack 5 CSVs do not have them).
        #  udevadm wait --settle --timeout 10 $(find ${pkgs.nvidia-jetpack.l4tCsv}/ -type f -exec grep '/dev/' {} \; | grep -v -e '\*' -e 'by-path' | cut -d',' -f2 | tr -d '\n') || true
        #
        # Investigate if globs pose a problem for JetPack 5/6.

        # TODO: This should be upstreamed.
        before = mkMerge [
          (mkIf config.virtualisation.docker.enable [ "docker.service" ])
          (mkIf config.virtualisation.podman.enable [ "podman.service" ])
        ];
      };

      hardware.nvidia-container-toolkit = {
        # TODO: Issues to address in nvidia-container-toolkit-cdi-generator:
        # - Warning about "Failed to locate symlink /etc/vulkan/icd.d/nvidia_icd.json" on the host
        # - Log reports "Generated CDI spec with version 0.8.0" but actual CDI JSON shows `"cdiVersion": "0.5.0"`

        csv-files =
          let
            inherit (pkgs.nvidia-jetpack) l4tCsv;
          in
          lib.map (fileName: "${l4tCsv}/${fileName}") l4tCsv.fileNames;

        # Must be set to "csv" when `csv-files` are provided.
        discovery-mode = mkForce "csv";

        # Unsupported.
        mount-nvidia-docker-1-directories = mkForce false;

        # Unsupported as Jetson doesn't provide the same binaries as other platforms; ours are captured by the CSV
        # files in l4tCsv and are always included in the container.
        mount-nvidia-executables = mkForce false;

        extraArgs = [
          # Jetson requires `--driver-root`
          "--driver-root"
          pkgs.nvidia-jetpack.containerDeps.outPath
          # `--dev-root` defaults to `/dev`, but it should be root
          "--dev-root"
          "/"
          # The cdi generation creates a hook for us mounting "libcuda.so.1::/usr/lib/aarch64-linux-gnu/tegra/libcuda.so".
          # Because the provided CSV does about the same thing, and we cannot disable the hook, we ignore the CSV entry.
          "--csv.ignore-pattern"
          "/usr/lib/aarch64-linux-gnu/tegra/libcuda.so" # For JetPack 5
          "--csv.ignore-pattern"
          "/usr/lib/aarch64-linux-gnu/nvidia/libcuda.so" # For JetPack 6
        ];

        # NOTE: The upstream NixOS module for `nvidia-container-toolkit` includes `hardware.nvidia.package` in the list
        # of mounts, but we don't want that because that's for desktop/datacenter GPU drivers, so we use `mkForce`
        # to make the list of mounts anew.
        mounts =
          let
            makePassthroughMount = path: {
              hostPath = path;
              containerPath = path;
            };

            # For reference, the packages used to create driverLink are here:
            # https://github.com/NixOS/nixpkgs/blob/ce01daebf8489ba97bd1609d185ea276efdeb121/nixos/modules/hardware/graphics.nix#L10
            driverLinkConstituents = [
              config.hardware.graphics.package
              # Recall that `config.hardware.graphics.extraPackages` creates l4tCoreWrapper inline, which
              # symlinks to l4t-core. In order for those symlinks to resolve, their target must also be included
              # in the list of mounts; as such, we need l4t-core.
              pkgs.nvidia-jetpack.l4t-core
            ]
            ++ config.hardware.graphics.extraPackages;
          in
          mkForce (
            lib.map makePassthroughMount [
              "${lib.getLib pkgs.glibc}/lib"
              "${lib.getLib pkgs.glibc}/lib64"
              pkgs.addDriverRunpath.driverLink
            ]
            # NOTE: Is it not enough to include the driverLink -- the symlinks to the Nix store won't resolve.
            # We must include all the the packages which go into producing it as well.
            # TODO: This can/should be upstreamed. Ultimately, this behavior is very similar to the
            # nix-required-mounts hook, which can add the GPU to the sandbox, where we also need the closure
            # of all packages involved.
            ++ lib.map (drv: makePassthroughMount drv.outPath) driverLinkConstituents
          );
      };
    })
  ]);
}
