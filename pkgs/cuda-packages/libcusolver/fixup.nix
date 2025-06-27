# NOTE: All fixups must be at least binary functions to avoid callPackage adding override attributes.
{ lib
, libcublas
, libcusparse ? null
, libnvjitlink ? null
, cudaAtLeast
}:
prevAttrs: {
  buildInputs = prevAttrs.buildInputs or [ ] ++ [
    (lib.getLib libcublas)
  ] ++ lib.lists.optionals (cudaAtLeast "12") [
    (lib.getLib libcusparse)
    (lib.getLib libnvjitlink)
  ];
}
