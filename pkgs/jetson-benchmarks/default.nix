{ stdenvNoCC
, fetchFromGitHub
, python3
, runCommand
, lib
, writeShellApplication
, writeShellScript
, coreutils
, unzip
, wget
, gnupatch
, cudaPackages
, makeWrapper

, targetSom

, benchmarkSrc ? fetchFromGitHub {
    owner = "NVIDIA-AI-IOT";
    repo = "jetson_benchmarks";
    rev = "43892b9ec64abdfabb4c18e19f301d9d4358f5ea";
    sha256 = "sha256-u11iBbEALOMite/ivm95TAnmXB71i9OjdNnRd0e1cHg=";
  }

  # disable some system checks such as closing all apps which prevent the benchmark
  # from being run non-interactively and others like the ones that set the
  # clocks and nvpmodels
, disableDisruptiveSystemCheck ? true
}:
let
  pythonEnv = python3.withPackages (ps: with ps; [ numpy pandas ]);

  benchmarkFileMapping = rec {
    "orin-agx" = {
      csvFile = "orin-benchmarks.csv";
      modelDir = "agx_orin_benchmarks_models";
    };
    "xavier-agx" = {
      csvFile = "xavier-benchmarks.csv";
      modelDir = "agx_xavier_benchmarks_models";
    };
    "nx" = {
      csvFile = "nx-benchmarks.csv";
      modelDir = "nx_benchmarks_models";
    };
  };
  # nvidia uses a custom script to download the model so make a derivation to do it
  models = stdenvNoCC.mkDerivation {
    name = "jetson-benchmarks-models";
    nativeBuildInputs = [ pythonEnv wget unzip coreutils ];

    builder = writeShellScript "builder.sh" ''
      source $stdenv/setup

      mkdir -p $out/${benchmarkFileMapping.orin-agx.modelDir}
      python3 "${benchmarkSrc}/utils/download_models.py" \
        --all \
        --csv_file_path "${benchmarkSrc}/benchmark_csv/${benchmarkFileMapping.orin-agx.csvFile}" \
        --save_dir $out/${benchmarkFileMapping.orin-agx.modelDir}

      mkdir -p $out/${benchmarkFileMapping.xavier-agx.modelDir}
      python3 "${benchmarkSrc}/utils/download_models.py" \
        --all \
        --csv_file_path "${benchmarkSrc}/benchmark_csv/${benchmarkFileMapping.xavier-agx.csvFile}" \
        --save_dir $out/${benchmarkFileMapping.xavier-agx.modelDir}

      mkdir -p $out/${benchmarkFileMapping.nx.modelDir}
      python3 "${benchmarkSrc}/utils/download_models.py" \
        --all \
        --csv_file_path "${benchmarkSrc}/benchmark_csv/${benchmarkFileMapping.nx.csvFile}" \
        --save_dir $out/${benchmarkFileMapping.nx.modelDir}
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-gcuWf/Vt1p8aZLt3tnTpUcTD0ZIpL76JxofZQjAlGjg=";
  };

  runScriptDep = [ pythonEnv cudaPackages.tensorrt coreutils ];
in
stdenvNoCC.mkDerivation {
  name = "jetson-benchmarks";

  src = benchmarkSrc;
  inherit models;

  patches = [ ]
    ++ lib.optional disableDisruptiveSystemCheck ./0001-disable-disruptive-system_check.patch;

  nativeBuildInputs = [ coreutils makeWrapper ];

  dontBuild = true;

  postPatch = ''
    substituteInPlace utils/load_store_engine.py --replace "/usr/src/tensorrt" "${cudaPackages.tensorrt}"
    substituteInPlace utils/utilities.py --replace "/usr/src/tensorrt" "${cudaPackages.tensorrt}"
  '';
  installPhase = ''
    mkdir -p models
    cp -r $models/. models

    mkdir -p $out
    cp -r ./. $out

    mkdir -p $out/bin
    cp -r ${./scripts}/. $out/bin
    chmod +x $out/bin/*
  '';
  postFixup = ''
    wrapProgram $out/bin/run-jetson-benchmarks \
      --prefix PATH ":" ${lib.makeBinPath runScriptDep} \
      --set BENCHMARK_CSV_FILE ${benchmarkFileMapping.${targetSom}.csvFile} \
      --set MODEL_DIR ${benchmarkFileMapping.${targetSom}.modelDir}
  '';
}
