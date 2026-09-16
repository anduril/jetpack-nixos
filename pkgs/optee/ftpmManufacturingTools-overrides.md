# fTPM manufacturing tools override hooks

`ftpmManufacturingTools.nix` exposes a few `overrideAttrs`-settable hooks so
site-specific CA/CSR logic can be substituted for NVIDIA's stub
implementations without patching the vendored source.

## `vendored_ftpm_manufacturer_gen_ek_csr` / `vendored_ftpm_manufacturer_ca_simulator`

JP5/JP6 only. Each takes a single script (shell, or a `writeShellScript`
wrapper around anything else, e.g. Python) that replaces
`ftpm_manufacturer_gen_ek_csr.sh` / `ftpm_manufacturer_ca_simulator.sh`
respectively. See the NVIDIA docs section "Generating ODM EKB" for the
script contract (args, expected input/output file naming under
`ftpm_out`/`ca_out` relative to the caller's cwd).

```nix
ftpmManufacturingTools.overrideAttrs (_: _: {
  vendored_ftpm_manufacturer_ca_simulator = pkgs.writeShellScript "ca-sign-shim" ''
    exec ${pythonEnv}/bin/python3 ${./scripts}/ftpm_ca_sign_shim.py "$@"
  '';
});
```

A multi-file implementation (e.g. a Python entrypoint importing a shared
helper module) doesn't need multi-file support from this hook: bundle the
directory with `${./scripts}` inside the wrapper above, and the whole
directory lands in the store together so the sibling import resolves.

## `vendored_ftpm_ca_class`

JP7 only. JP6 and earlier expose CA signing as separate shell scripts,
but JP7 removed that entirely: NVIDIA's `odm_ekb_gen.py` now signs CSRs by
instantiating `SimulatorCA` (a `CAInterface` subclass defined in
`lib/ca_signing.py`) directly in Python, with no config flag or command-line
switch to select a different backend. NVIDIA's own docs say to do this by
literally editing `odm_ekb_gen.py` to instantiate your own class instead.

This hook does that substitution for you. Supply a single Python file
defining a class named exactly `CustomCA` that subclasses `CAInterface`
(see `lib/ca_signing.py` in the built package, or the interface summary
below), and it's installed as `lib/custom_ca.py` and substituted in place
of `SimulatorCA` at import time.

`CAInterface` requires six methods:

- `initialize(output_path: str) -> None`
- `sign_ek_csr(ek_csr_der: bytes, ek_type: str, device_sn: str) -> str`
- `sign_sid_csr(sid_csr_der: bytes, device_sn: str) -> str`
- `verify_cert_chain(cert_der_file: str) -> bool`
- `get_ca_cert_pem(self) -> bytes`
- `get_root_cert_pem(self) -> bytes`

The simplest starting point is to subclass NVIDIA's own `SimulatorCA`
(which already implements all six against a self-signed test CA chain) and
override only what needs to talk to a real CA:

```python
# custom_ca.py
from lib.ca_signing import SimulatorCA

class CustomCA(SimulatorCA):
    def sign_ek_csr(self, ek_csr_der, ek_type, device_sn):
        # ... call out to your real CA instead of self-signing ...
        return super().sign_ek_csr(ek_csr_der, ek_type, device_sn)
```

```nix
ftpmManufacturingTools.overrideAttrs (_: _: {
  vendored_ftpm_ca_class = ./custom_ca.py;
});
```

Left `null` (the default), `odm_ekb_gen.py` is unmodified and continues to
use NVIDIA's `SimulatorCA`.
