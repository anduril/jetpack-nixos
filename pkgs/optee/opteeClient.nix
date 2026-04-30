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
    ]) ++ [
      (fetchpatch {
        name = "tee-supplicant-add-systemd-sd_notify-support.patch";
        url = "https://github.com/OP-TEE/optee_client/commit/a5b1ffcd26e328af0bbf18ab448a38ecd558e05c.patch";
        stripLen = 1;
        extraPrefix = "optee/optee_client/";
        hash = "sha256-85DYu8BmWgpeowLMptLwXb77MWytNgvwqSZuPGtBFG4=";
      })
    ];

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
