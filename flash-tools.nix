{ stdenv, lib, makeWrapper, bzip2_1_1, fetchurl, python3, python2, perl, xxd,
  libxml2, coreutils, gnugrep, gnused, gnutar, gawk, which, gzip, cpio,
  bintools-unwrapped, findutils, util-linux, dosfstools, lz4, gcc, dtc,

  bspSrc, version,
}:

let
  flash-tools = stdenv.mkDerivation {
    pname = "flash-tools";
    inherit version;

    src = bspSrc;

    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [
      (python3.withPackages (p: with p; [ pyyaml ]))
      python2
      perl
    ]; # BUP_payload needs python2 :(  Others need python3

    postPatch = ''
      for filename in bootloader/BUP_generator.py bootloader/rollback/rollback_parser.py; do
        substituteInPlace $filename \
          --replace "#!/usr/bin/python" "#!/usr/bin/env python2"
      done

      # Needed in Jetpack 5
      substituteInPlace flash.sh \
        --replace /usr/bin/xmllint ${libxml2}/bin/xmllint

      # Remove stuff not needed for flashing
      find . -iname '*.deb' -delete
      find . -iname '*.tbz2' -delete

      # We should never be flashing upstream's kernel, so just remove it so we get errors if it is used
      #rm -f kernel/Image*

      # Flash script looks for this file
      mv nv_tegra/bsp_version .
      rm -rf nv_tegra
      mkdir nv_tegra
      mv bsp_version nv_tegra
    '';

    # Create update payloads with:
    # ./l4t_generate_soc_bup.sh t19x

    dontConfigure = true;
    dontBuild = true;
    noDumpEnvVars = true;

    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';

    # Stuff to put into PATH for flash.sh
    # wrapProgram doesn't work here because it refers to the wrapped program by
    # absolute path, and flash-script copies the entire flash-tools dir before
    # running
    passthru.flashDeps = [
      coreutils gnugrep gnused gnutar gawk xxd which gzip cpio bintools-unwrapped
      findutils python3 util-linux dosfstools lz4

      # Needed by bootloader/tegraflash_impl_t234.py
      gcc dtc
    ];
  };

in flash-tools
