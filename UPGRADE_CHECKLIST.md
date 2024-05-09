### Updating
- [ ] Update `l4tVersion`, `jetpackVersion`, and `cudaVersion` in default.nix
- [ ] Update branch/revision/sha256s in:
    - [ ] `default.nix`
    - [ ] `kernel/default.nix`
    - [ ] `uefi-firmware.nix`
    - [ ] Grep for "sha256 = ", see if there is anything else not covered
- [ ] Update the kernel version in `kernel/default.nix` if it chaged.
- [ ] Grep for the previous version strings e.g. "35.4.1"
- [ ] Compare files from `unpackedDebs` before and after
- [ ] Grep for NvOsLibraryLoad in libraries from debs to see if any new packages not already handled in l4t use the function
- [ ] Ensure the soc variants in `modules/flash-script.nix` match those in `jetson_board_spec.cfg` from BSP
- [ ] Ensure logic in `ota-utils/ota_helpers.func` matches `nvidia-l4t-init/opt/nvidia/nv-l4t-bootloader-config.sh`
- [ ] Run `nix build .#genL4tJson` and copy output to `pkgs/containers/l4t.json`
- [ ] Run `skopeo inspect docker://nvcr.io/nvidia/l4t-jetpack/r${l4tVersion}` to udpate FOD for l4t-jetpack OCI image in `./pkgs/tests/default.nix`

### Testing
- [ ] Run `nix flake check`
- [ ] Build installer ISO
- [ ] Flash all variants
- [ ] Boot all variants
- [ ] Run our (Anduril's) internal automated device tests
