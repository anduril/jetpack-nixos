{ runCommand
, l4tMajorMinorPatchVersion
, optee-os
}:
runCommand "pkcs11ta-${l4tMajorMinorPatchVersion}" { } ''
  install -Dm ${optee-os}/ta/pkcs11/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta $out
''
