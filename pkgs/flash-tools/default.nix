{ stdenv
, lib
, makeWrapper
, bzip2_1_1
, fetchurl
, python3
, perl
, xxd
, libxml2
, coreutils
, gnugrep
, gnused
, gnutar
, gawk
, which
, gzip
, cpio
, bintools-unwrapped
, findutils
, util-linux
, dosfstools
, lz4
, gcc
, dtc
, qemu
, runtimeShell
, fetchzip
, bc
, openssl
, bspSrc
, l4tVersion
,
}:

let
  # This "overlay" can be found here: https://developer.nvidia.com/embedded/jetson-linux-r3521
  # It includes the tegra_v3_oemkey.yaml file which was missing in Jetpack 5.1, and still isn't in Jetpack 5.1.1 :(
  secureboot_overlay = fetchzip {
    url = "https://developer.download.nvidia.com/embedded/L4T/r35_Release_v2.1/secureboot_overlay_35.2.1.tbz2";
    sha256 = "sha256-mgtgI/MNTHRbmiJdfg6Nl1ZnEw6Swniaej2/5z/bpoI=";
  };

  mb1_overlay = fetchzip {
    url = "https://developer.download.nvidia.com/embedded/L4T/r35_Release_v3.1/mb1_35.3.1_overlay.tbz2";
    sha256 = "sha256-Ytp3vESEyPPwEXVSVjhCWEglgmK82To605vRbMhjv50=";
  };
  usb_overlay = fetchzip {
    url = "https://developer.download.nvidia.com/embedded/L4T/r35_Release_v3.1/overlay_xusb_35.3.1.tbz2";
    sha256 = "sha256-3ZH2gPKilZfexg2YdnppDBRSBO0oQVDBkjBl1Iw+iOw=";
  };

  flash-tools = stdenv.mkDerivation {
    pname = "flash-tools";
    version = l4tVersion;

    src = bspSrc;

    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [
      (python3.withPackages (p: with p; [ pyyaml ]))
      perl
    ];

    patches = [ ./flash-tools.patch ./flash-tools-secureboot.patch ];

    postPatch = ''
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

      # This file was missing from Jetpack 5.1, and still isn't in Jetpack 5.1.1 :(
      cp ${secureboot_overlay}/bootloader/tegrasign_v3_oemkey.yaml bootloader/

      # Apply additional overlays added after 35.3.1 was released
      cp ${mb1_overlay}/bootloader/* bootloader/
      cp ${usb_overlay}/bootloader/* bootloader/
      chmod u+w -R bootloader
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
      coreutils
      gnugrep
      gnused
      gnutar
      gawk
      xxd
      which
      gzip
      cpio
      bintools-unwrapped
      findutils
      python3
      util-linux
      dosfstools
      lz4
      bc
      openssl

      # Needed by bootloader/tegraflash_impl_t234.py
      gcc
      dtc
    ];
  };

in
flash-tools
