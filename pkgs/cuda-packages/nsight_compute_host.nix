{ alsa-lib
, buildFHSUserEnv
, buildFromDebs
, dbus
, debs
, expat
, fontconfig
, ncurses5
, noto-fonts
, nsight_compute_target
, nspr
, nss
, qt6
, stdenv
, xkeyboard_config
, xorg
,
}:
let
  finalAttrs = {
    pname = "nsight-compute-host";
    inherit (nsight_compute_target) version; # Host must match target.
    srcs = debs.common."nsight-compute-${finalAttrs.version}".src;
    dontAutoPatchelf = true;
    postPatch =
      let
        mkPostPatch = arch: ''
          mkdir -p host
          cp -r "opt/nvidia/nsight-compute/${finalAttrs.version}/host/${arch}" host
          cp -r "opt/nvidia/nsight-compute/${finalAttrs.version}/extras" .
          cp -r "opt/nvidia/nsight-compute/${finalAttrs.version}/sections" .
          rm -r opt

          # ncu requires that it remains under its original directory so symlink instead of copying
          # things out
          mkdir -p bin
          ln -sfv ../host/${arch}/ncu-ui ./bin/ncu-ui
        '';
      in
      if stdenv.hostPlatform.system == "x86_64-linux" then
        mkPostPatch "linux-desktop-glibc_2_11_3-x64"
      else if stdenv.hostPlatform.system == "aarch64-linux" then
        mkPostPatch "linux-v4l_l4t-t210-a64"
      else
        throw "Unsupported architecture";
    meta.platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
  nsight_out = buildFromDebs finalAttrs;
in
# ncu-ui has some hardcoded /usr access so use fhs instead of trying to patchelf
  # it also comes with its own qt6 .so, trying to use Nix qt6 libs results in weird
  # behavior(blank window) so just supply qt6 dependency instead of qt6 itself
buildFHSUserEnv {
  pname = "ncu-ui";
  inherit (nsight_out) version;
  targetPkgs =
    pkgs:
    (
      [
        ncurses5
        xorg.libxcb
        fontconfig
        noto-fonts
        dbus
        nss
        xorg.libXcomposite
        xorg.libXdamage
        alsa-lib
        xorg.libXtst
        xorg.libSM
        xorg.libICE
        xorg.libXfixes
        xkeyboard_config
        expat
        nspr
      ]
      ++ qt6.qtbase.propagatedBuildInputs
      ++ qt6.qtwebengine.propagatedBuildInputs
    );
  runScript = ''
    ${nsight_out}/bin/ncu-ui $*
  '';
}
