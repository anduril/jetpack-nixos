{ runCommand, l4tCsv, unpackedDebsFilenames, l4tAtLeast, python3, dpkg }:

let
  l4tCsvFilename = if l4tAtLeast "36" then "drivers.csv" else "l4t.csv";
in
runCommand "l4t.json" { nativeBuildInputs = [ python3 dpkg ]; } ''
  python3 ${./gen_l4t_json.py} ${l4tCsv}/${l4tCsvFilename} ${unpackedDebsFilenames} > $out
''
