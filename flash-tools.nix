{ stdenv, lib, makeWrapper, bzip2_1_1, fetchurl, python3, python2, perl, xxd,
  libxml2, coreutils, gnugrep, gnused, gnutar, gawk, which, gzip, cpio,
  bintools-unwrapped, findutils, util-linux, dosfstools, lz4, gcc, dtc, qemu,
  runtimeShell,

  bspSrc, l4tVersion,
}:

let
  flash-tools = stdenv.mkDerivation {
    pname = "flash-tools";
    version = l4tVersion;

    src = bspSrc;

    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [
      (python3.withPackages (p: with p; [ pyyaml ]))
      python2
      perl
    ]; # BUP_payload needs python2 :(  Others need python3

    patches = [ ./flash-tools.patch ];

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
    '' + (lib.optionalString (!stdenv.hostPlatform.isx86) ''
      # Wrap x86 binaries in qemu
      pushd bootloader/ >/dev/null
      for filename in chkbdinfo mkbctpart mkbootimg mksparse tegrabct_v2 tegradevflash_v2 tegrahost_v2 tegrakeyhash tegraopenssl tegraparser_v2 tegrarcm_v2 tegrasign_v2; do
        mv "$filename" ."$filename"-wrapped
        cat >"$filename" <<EOF
      #!${runtimeShell}
      exec -a "\$0" ${qemu}/bin/qemu-i386 "$out/bootloader/.$filename-wrapped" "\$@"
      EOF
        chmod +x "$filename"
      done
      popd >/dev/null
    '');

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
