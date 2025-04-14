# NOTE: All fixups must be at least binary functions to avoid callPackage adding override attributes.
{ l4t-core
, l4t-cuda
, lib
, flags
}:
prevAttrs: { buildInputs = prevAttrs.buildInputs or [ ] ++ [ l4t-core l4t-cuda ]; }
