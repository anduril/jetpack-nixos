# Patches from upstream tianocore/edk2 to enable build of OpenSSL 1.1.1t inside
# edk2 tree
{fetchpatch2}:
[
  # CryptoPkg/OpensslLib: Add native instruction support for IA32
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/03f708090b9da25909935e556c351a4d9445fd3f.patch";
    hash = "sha256-kWTzzQjGJdYzoaMckReUQHl5IkpHFApG9zRVQRavbAE=";
  })

  # CryptoPkg/OpensslLib: Commit the auto-generated assembly files for IA32
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/4102950a21dc726239505b8f7b8e017b6e9175ec.patch";
    hash = "sha256-DaqMQJN9axlXVF3QM2MPhzRh0yq8WuWLDg3El+lIN+M=";
  })

  # CryptoPkg/OpensslLib: Update generated files for native X64
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/a8e8c43a0ef25af133dc5ef1021befd897f71b12.patch";
    hash = "sha256-4tD8AR78fYXFCcHHAgEYiSjcYFxdoObykNNocIuq1ac=";
  })

  # CryptoPkg: Add LOONGARCH64 architecture for EDK2 CI.
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/c5f4b4fd03c9d8e2ba9bfa0e13065f4dc2be474e.patch";
    hash = "sha256-dXQdHDJzkWy0vOpXQHNPGQus3ATvKnsSq0yriidy5hY=";
  })

  # CryptoPkg/Library/OpensslLib: Combine all performance optimized INFs
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/ea6d859b50b692577c4ccbeac0fb8686fad83a6e.patch";
    hash = "sha256-XyF1+wBxy1nQhaPDDjNj1voHRvHd+IbkRiq1TOJwn1g=";
  })

  # CryptoPkg/Library/OpensslLib: Produce consistent set of APIs
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/e75951ca896ee2146f2133d2dc425e2d21861e6b.patch";
    hash = "sha256-3RAXVbm/rjbGKpnaYqoqY33rl8nyy80lsBBdBt7yXKo=";
  })

  # CryptoPkg/Library/OpensslLib: Remove PrintLib from INF files
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/a57b4c11a51d9c313735b3af5c69cc371c74e11f.patch";
    hash = "sha256-Q9NAWwSa7uqXnFVmtk5s9YEpe8FdXJM70PLwTweKaVk=";
  })

  # Revert "CryptoPkg: Update process_files.pl to auto add PCD config option"
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/3b46a1e24339b03f04be80ebf21d03fd98c490de.patch";
    hash = "sha256-L26HBzuQQVLHLSo9tPF7qSdMRaUSDmmWlvSeZE2S4tU=";
  })

  # CryptoPkg/Library/OpensslLib: Update process_files.pl INF generation
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/d79295b5c57fddfff207c5c97d70ba6de635e17a.patch";
    hash = "sha256-wJrQsvcwQbCptl58YMyi5dokFjoWKoqy08dYyszy9a0=";
  })

  # CryptoPkg/Library/OpensslLib: Add generated flag to Accel INF
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/0882d6a32d3db7c506823c317dc2f756d30f6a91.patch";
    hash = "sha256-H59qcKYv72vMsROKImHPncEFBermt1Jchcxj0T6hDdI=";
  })

  # CryptoPkg/Library/OpensslLib: update auto-generated files
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/4fcd5d2620386c039aa607ae5ed092624ad9543d.patch";
    hash = "sha256-Uhwyuu0q0oPvKF0zFW/D8dAYOJ/2YyEG3pfVQH9khkc=";
  })

  # CryptoPkg/OpensslLib: Upgrade OpenSSL to 1.1.1t
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/4ca4041b0dbb310109d9cb047ed428a0082df395.patch";
    hash = "sha256-XPCqfQQekvxF33Q/QEkj14Zpxf/s+caNyQlSfNzwuD0=";
    excludes = [
      "CryptoPkg/Library/OpensslLib/openssl"
    ];
  })

  # CryptoPkg/Library: add -Wno-unused-but-set-variable for openssl
  (fetchpatch2 {
    url = "https://github.com/tianocore/edk2/commit/410ca0ff94a42ee541dd6ceab70ea974eeb7e500.patch";
    hash = "sha256-WMKSIgYEaNNVcXD3UCp38YQU8qy63uBHDexl4+3c9LM=";
  })
]
