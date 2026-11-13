{ lib }:
let
  inherit (lib) mkOption types;
in
{
  type = types.oneOf [
    types.path
    types.str
    (types.attrTag {
      uriFile = mkOption {
        type = types.path;
        description = "File containing one PKCS#11 URI.";
      };
    })
  ];

  render =
    name: value:
    if builtins.isAttrs value && !lib.isDerivation value && value ? uriFile then
      {
        # A failed substitution in a tool argument does not stop the tool.
        verify = ''${name}=$(python3 ${./pkcs11-uri-from-file.py} ${lib.escapeShellArg "${value.uriFile}"}) || exit 1'';
        argument = ''"${"$"}${name}"'';
      }
    else
      {
        verify = "";
        argument = lib.escapeShellArg "${value}";
      };
}
