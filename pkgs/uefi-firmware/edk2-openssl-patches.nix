# Patches from upstream tianocore/edk2 to enable build of OpenSSL 1.1.1t inside
# edk2 tree
{ fetchpatch2 }:
let
  # Needs to use fetchpatch2 to handle "git extended headers", which include
  # lines with semantic content like "rename from" and "rename to".
  # However, it also includes "index" lines which include the git revision(s) the patch was initially created from.
  # These lines may include revisions of differing length, based on how Github generates them.
  # fetchpatch2 does not filter out, but probably should
  fetchgitpatch = args: fetchpatch2 (args // {
    postFetch = (args.postFetch or "") + ''
      sed -i \
        -e '/^index /d' \
        -e '/^similarity index /d' \
        -e '/^dissimilarity index /d' \
        $out
    '';
  });
in
[
  # CryptoPkg/OpensslLib: Add native instruction support for IA32
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/03f708090b9da25909935e556c351a4d9445fd3f.patch";
    hash = "sha256-nSAhWxYWzTYJYtk0GhuwKSngSXp2R7NboZ3Qs7ETHos=";
  })

  # CryptoPkg/OpensslLib: Commit the auto-generated assembly files for IA32
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/4102950a21dc726239505b8f7b8e017b6e9175ec.patch";
    hash = "sha256-DaqMQJN9axlXVF3QM2MPhzRh0yq8WuWLDg3El+lIN+M=";
  })

  # CryptoPkg/OpensslLib: Update generated files for native X64
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/a8e8c43a0ef25af133dc5ef1021befd897f71b12.patch";
    hash = "sha256-o7xXCRw3eT4LGpgvDeO6ZCBim4+XWJYaUyPwLIcTf4Q=";
  })

  # CryptoPkg: Add LOONGARCH64 architecture for EDK2 CI.
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/c5f4b4fd03c9d8e2ba9bfa0e13065f4dc2be474e.patch";
    hash = "sha256-2cTMGRX78z+HPTz2yl/RTiJK+Ze2lu0QkKvqtVZuTYU=";
  })

  # CryptoPkg/Library/OpensslLib: Combine all performance optimized INFs
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/ea6d859b50b692577c4ccbeac0fb8686fad83a6e.patch";
    hash = "sha256-7uiubCI51L6LrmYzesKF4p/xCC6dsVR3M2h1H337/zw=";
  })

  # CryptoPkg/Library/OpensslLib: Produce consistent set of APIs
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/e75951ca896ee2146f2133d2dc425e2d21861e6b.patch";
    hash = "sha256-bxV1hZ1c+i+CgZE1LsJy82pLgcMDq3Kkv4peZZDHZXE=";
  })

  # CryptoPkg/Library/OpensslLib: Remove PrintLib from INF files
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/a57b4c11a51d9c313735b3af5c69cc371c74e11f.patch";
    hash = "sha256-jM8/Nngzw5qFsLJQzKSJHQC8vP1Vdk1kHotVfq/NzGc=";
  })

  # Revert "CryptoPkg: Update process_files.pl to auto add PCD config option"
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/3b46a1e24339b03f04be80ebf21d03fd98c490de.patch";
    hash = "sha256-CX4O1lmHrGnJi9AChKh5hFC4sJikdcLCwOdG9/drwUk=";
  })

  # CryptoPkg/Library/OpensslLib: Update process_files.pl INF generation
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/d79295b5c57fddfff207c5c97d70ba6de635e17a.patch";
    hash = "sha256-oHPFcny1eS1kLNwGUPhXaLpOsBIQxy76tkKgM7QJ7yU=";
  })

  # CryptoPkg/Library/OpensslLib: Add generated flag to Accel INF
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/0882d6a32d3db7c506823c317dc2f756d30f6a91.patch";
    hash = "sha256-XbH4N/sKs6aJ6IfFYdy2f2T8mX1/QIuukeSrRxAYL2w=";
  })

  # CryptoPkg/Library/OpensslLib: update auto-generated files
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/4fcd5d2620386c039aa607ae5ed092624ad9543d.patch";
    hash = "sha256-yI4nd3j+QqpIqENFg1qyi5KtKv8DEkh3XrvYw3oS2xo=";
  })

  # CryptoPkg/OpensslLib: Upgrade OpenSSL to 1.1.1t
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/4ca4041b0dbb310109d9cb047ed428a0082df395.patch";
    hash = "sha256-w6+5xunP9PcShkLFXBldMq/U5bcs2VfTjvIYoedIyWg=";
    excludes = [
      "CryptoPkg/Library/OpensslLib/openssl"
    ];
  })

  # CryptoPkg/Library: add -Wno-unused-but-set-variable for openssl
  (fetchgitpatch {
    url = "https://github.com/tianocore/edk2/commit/410ca0ff94a42ee541dd6ceab70ea974eeb7e500.patch";
    hash = "sha256-hmWkWTj6J1uhXKXynBWda455buTmbnB4GMu2+2sPYxY=";
  })
]
