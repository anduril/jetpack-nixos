# NVIDIA's Tegra kernels gate scripts/sign-file behind debian/scripts/sign-module
# in scripts/Makefile.modinst. That script's `#!/bin/bash -eu` shebang fails in
# the Nix sandbox (no /bin/bash), so signing silently no-ops and every module
# installs unsigned despite CONFIG_MODULE_SIG_ALL=y.
#
# Patch the shebang to an absolute bash path so the script runs.
if [ -f debian/scripts/sign-module ]; then
  patchShebangs debian/scripts/sign-module
fi
