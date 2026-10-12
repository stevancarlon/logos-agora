# Match Basecamp 0.3.2's locked Windows toolchain, including its Qt build features.
let
  logos = builtins.getFlake "github:logos-co/logos-nix/6e0f4a7120fced10829b0b3a698ff619a11d4605";
  pkgs = logos.lib.mkWindowsPkgs { buildSystem = "x86_64-linux"; };
  app = pkgs.stdenv.mkDerivation {
    pname = "agora-windows-native";
    version = "0.3.0";
    src = pkgs.lib.cleanSource ../native;
    nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.pkg-config pkgs.qt6.wrapQtAppsHook ];
    buildInputs = [ pkgs.qt6.qtbase pkgs.qt6.qtdeclarative pkgs.qt6.qtmultimedia pkgs.openssl ];
    cmakeFlags = [ "-DAGORA_EXPECTED_QT_VERSION=${pkgs.qt6.qtbase.version}" ]
      ++ (pkgs.logosQtCrossCmakeFlags or []);
    dontWrapQtApps = true;
  };
in {
  native = app;
  multimedia = pkgs.qt6.qtmultimedia;
  qtVersion = pkgs.qt6.qtbase.version;
}
