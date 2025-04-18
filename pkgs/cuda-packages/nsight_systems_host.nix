{ alsa-lib
, buildFHSUserEnv
, buildFromDebs
, dbus
, debs
, expat
, fontconfig
, ncurses5
, noto-fonts
, nsight_systems_target
, nsightSystemSrcs ? null
, nspr
, nss
, qt6
, requireFile
, stdenv
, xkeyboard_config
, xorg
,
}:
let
  finalAttrs = {
    pname = "nsight-systems-host";
    inherit (nsight_systems_target) version; # Host must match target.
    srcs =
      if nsightSystemSrcs == null then
        (
          if stdenv.hostPlatform.system == "x86_64-linux" then
            requireFile
              rec {
                name = "NsightSystems-linux-public-2022.5.2.120-3231674.deb";
                sha256 = "011f1vxrmxnip02zmlsb224cc01nviva2070qadkwhmz409sjxag";
                message = ''
                  For Jetpack 5.1, Nvidia doesn't upload the corresponding nsight system x86_64 version to the deb repo, so it need to be fetched using sdkmanager

                  Once you have obtained the file, please use the following commands and re-run the installation:

                  nix-prefetch-url file://path/to/${name}
                '';
              }
          else if stdenv.hostPlatform.system == "aarch64-linux" then
            debs.common."nsight-systems-${finalAttrs.version}".src
          else
            throw "Unsupported architecture"
        )
      else
        nsightSystemSrcs;
    phases = [
      "unpackPhase"
      "patchPhase"
      "installPhase"
    ];
    postPatch =
      let
        mkPostPatch = arch: ''
          mv opt/nvidia/nsight-systems/${finalAttrs.version}/host-${arch} .
          rm -r opt

          mkdir -p bin
          # nsys requires that it remains under its original directory so symlink instead of copying
          # things out
          ln -sfv ../host-${arch}/nsys-ui ./bin/nsys-ui
        '';
      in
      if stdenv.hostPlatform.system == "x86_64-linux" then
        mkPostPatch "linux-x64"
      else if stdenv.hostPlatform.system == "aarch64-linux" then
        mkPostPatch "linux-armv8"
      else
        throw "Unsupported architecture";
    meta.platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
  nsight_out = buildFromDebs finalAttrs;
in
# nsys-ui has some hardcoded /usr access so use fhs instead of trying to patchelf
  # it also comes with its own qt6 .so, trying to use Nix qt6 libs results in weird
  # behavior(blank window) so just supply qt6 dependency instead of qt6 itself
buildFHSUserEnv {
  pname = "nsys-ui";
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
    ${nsight_out}/bin/nsys-ui $*
  '';
}
