{ runCommand, buildPackages, unpackedDebsFilenames, l4tAtLeast }:

let
  l4tCsvFilename = if l4tAtLeast "36" then "drivers.csv" else "l4t.csv";
in
runCommand "l4t.json" { nativeBuildInputs = [ buildPackages.python3 buildPackages.dpkg ]; } ''
  python3 ${./gen_l4t_json.py} ${l4tCsv}/${l4tCsvFilename} ${unpackedDebsFilenames} > $out
''
