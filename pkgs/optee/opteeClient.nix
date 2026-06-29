{ stdenv
, gitRepos
, l4tMajorMinorPatchVersion
, l4tAtLeast
, fetchpatch
, pkg-config
, libuuid
}:
stdenv.mkDerivation {
  pname = "optee_client";
  version = l4tMajorMinorPatchVersion;
  src = gitRepos."tegra/optee-src/nv-optee";

  # Patching strategy for nv-optee's optee_client (forked from upstream
  # OP-TEE/optee_client).
  #
  # r35 only: Upstream tee-supplicant prepends hardcoded paths. Patch
  # 0001 removes that behaviour, and we backport the runtime TA-load-path
  # feature (f3845d8). Both are already present in r36+.
  #
  # r35 & r36 only: nv-optee carries an extra nvme_rpmb.c source that
  # isn't in upstream OP-TEE/optee_client, so a straight fetchpatch of the
  # sd_notify commit (a5b1ffcd) would fail. Instead we:
  #   1. Drop nvme_rpmb.c from the Makefile (0002)
  #   2. Apply the sd_notify fetchpatch (a5b1ffcd)
  #   3. Restore nvme_rpmb.c in the Makefile (0003)
  # r38 already includes a5b1ffcd in its nv-optee baseline, so this
  # drop-fetchpatch-restore dance is unnecessary there.
  patches =
    (if l4tAtLeast "36" then [ ] else [
      ./0001-Don-t-prepend-foo-bar-baz-to-TEEC_LOAD_PATH.patch
      (fetchpatch {
        name = "tee-supplicant-Allow-for-TA-load-path-to-be-specified-at-runtime.patch";
        url = "https://github.com/OP-TEE/optee_client/commit/f3845d8bee3645eedfcc494be4db034c3c69e9ab.patch";
        stripLen = 1;
        extraPrefix = "optee/optee_client/";
        hash = "sha256-XjFpMbyXy74sqnc8l+EgTaPXqwwHcvni1Z68ShokTGc=";
      })
    ]) ++ (if l4tAtLeast "38" then [ ] else [
      ./0002-tee-supplicant-Makefile-drop-nvme-rpmb.patch
      (fetchpatch {
        name = "tee-supplicant-add-systemd-sd_notify-support.patch";
        url = "https://github.com/OP-TEE/optee_client/commit/a5b1ffcd26e328af0bbf18ab448a38ecd558e05c.patch";
        stripLen = 1;
        extraPrefix = "optee/optee_client/";
        hash = "sha256-QDE6wKxA3kvLfcb5ILZZqgJ7WC3UGFmuKtrRP7MwPfM=";
      })
      ./0003-tee-supplicant-Makefile-restore-nvme-rpmb.patch
    ]);

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libuuid ];

  enableParallelBuilding = true;

  makeFlags = [
    "-C optee/optee_client"
    "DESTDIR=$(out)"
    "SBINDIR=/sbin"
    "LIBDIR=/lib"
    "INCLUDEDIR=/include"
  ];

  meta.platforms = [ "aarch64-linux" ];
}
