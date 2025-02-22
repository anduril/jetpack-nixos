{ opteeStdenv, fetchpatch, gitRepos, l4tVersion, pkg-config, libuuid }:

opteeStdenv.mkDerivation {
  pname = "optee_client";
  version = l4tVersion;
  src = gitRepos."tegra/optee-src/nv-optee";
  patches = [
    ./0001-Don-t-prepend-foo-bar-baz-to-TEEC_LOAD_PATH.patch
    (fetchpatch {
      name = "tee-supplicant-Allow-for-TA-load-path-to-be-specified-at-runtime.patch";
      url = "https://github.com/OP-TEE/optee_client/commit/f3845d8bee3645eedfcc494be4db034c3c69e9ab.patch";
      stripLen = 1;
      extraPrefix = "optee/optee_client/";
      hash = "sha256-XjFpMbyXy74sqnc8l+EgTaPXqwwHcvni1Z68ShokTGc=";
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
