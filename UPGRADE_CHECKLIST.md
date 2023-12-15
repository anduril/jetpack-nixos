### Updating
- [ ] Update `l4tVersion`, `bspVersion`, and `cudaVersion` in default.nix
- [ ] Update branch/revision/sha256s in:
    - [ ] `kernel/default.nix`
    - [ ] `kernel/display-driver.nix`
    - [ ] `uefi-firmware.nix`
    - [ ] `optee.nix`
    - [ ] Grep for "sha256 = ", see if there is anything else not covered
- [ ] Grep for the previous version strings e.g. "35.3.1"
- [ ] Compare files from `unpackedDebs` before and after
- [ ] Ensure the soc variants in `modules/flash-script.nix` match those in jetson_board_spec.cfg from BSP
- [ ] Ensure logic in ota-utils/ota_helpers.func matches nvidia-l4t-init/opt/nvidia/nv-l4t-bootloader-config.sh
- [ ] Run `nix build .#genL4tJson` and copy output to `pkgs/containers/l4t.json`

### Testing
- [ ] Run `nix flake check`
- [ ] Build installer ISO
- [ ] Flash all variants
- [ ] Boot all variants
- [ ] Run our (Anduril's) internal automated device tests
