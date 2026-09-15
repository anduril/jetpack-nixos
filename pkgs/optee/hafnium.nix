{ lib
, stdenv
, buildPackages
, gitRepos
, l4tMajorMinorPatchVersion
}:

let
  l4tMajorVersion = lib.versions.major l4tMajorMinorPatchVersion;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "hafnium";
  version = l4tMajorMinorPatchVersion;

  socType =
    if l4tMajorVersion == "39" then "t264"
    else throw "Unknown SoC type: ${l4tMajorVersion}";

  src = gitRepos."tegra/hafnium-src/hafnium";

  patches = finalAttrs.extraPatches or [ ];
  extraPatches = [ ];

  postPatch = ''
    # Allow libfdt to use libfdt_config
    substituteInPlace dtc/BUILD.gn \
      --replace-fail 'visibility = [ ":gtest" ]' 'visibility = [ ":*" ]'
  '';

  dontPatchELF = true;
  dontStrip = true;
  hardeningDisable = [ "all" ];

  nativeBuildInputs = [
    buildPackages.gn
    buildPackages.ninja
    buildPackages.dtc
    (buildPackages.python3.withPackages (p: with p; [ pyelftools cryptography libfdt ]))
    buildPackages.llvmPackages.clang-unwrapped
    buildPackages.llvmPackages.bintools
  ];

  enableParallelBuilding = true;

  # --- GN Hook Configuration ---
  dontUseGnConfigure = true;

  configurePhase = ''
    runHook preConfigure

    local outDir="$PWD/out.hafnium.${finalAttrs.socType}"
    local toolchainLib="$(clang --print-resource-dir)"
    cd hafnium

    gn gen "$outDir" \
      --export-compile-commands \
      --args="project=\"//soc/${finalAttrs.socType}\" third_party_root=\"//..\" toolchain_lib=\"$toolchainLib\" enable_assertions=1"

    cd ..

    runHook postConfigure
  '';
  # --- Ninja Hook Configuration ---
  # Ninja's hook is standard and works fine:
  ninjaFlags = [
    "-C" "out.hafnium.${finalAttrs.socType}"
    "nvidia_${finalAttrs.socType}_clang/hafnium.bin"
  ];

  # Compile the SPMC device tree blob after Ninja finishes
  postBuild = ''
    dtc -I dts -O dtb \
      -o "out.hafnium.${finalAttrs.socType}/${finalAttrs.socType}_spmc.dtb" \
      hafnium/soc/${finalAttrs.socType}/manifests/${finalAttrs.socType}_spmc.dts0
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out

    ${buildPackages.nvidia-jetpack.fiptool}/bin/fiptool create \
      --tos-fw "out.hafnium.${finalAttrs.socType}/nvidia_${finalAttrs.socType}_clang/hafnium.bin" \
      --tos-fw-config "out.hafnium.${finalAttrs.socType}/${finalAttrs.socType}_spmc.dtb" \
      $out/hafnium_${finalAttrs.socType}.fip

    runHook postInstall
  '';

  meta = with lib; {
    description = "Hafnium Secure World Hypervisor for Jetson";
    platforms = platforms.aarch64;
  };
})