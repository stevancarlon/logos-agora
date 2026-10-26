# Match Basecamp 0.3.2's locked Windows toolchain, including its Qt build features.
let
  logos = builtins.getFlake "github:logos-co/logos-nix/6e0f4a7120fced10829b0b3a698ff619a11d4605";
  pkgs = logos.lib.mkWindowsPkgs { buildSystem = "x86_64-linux"; };
  # Upstream's blanket MinGW64 broken flag cites third-party DLL staging
  # (nixpkgs PR 295344, comment 1992263658). Build only FFmpeg's built-in
  # codecs here, without that external codec dependency tree; host execution
  # and dependency checks must still prove this distinct build works.
  ffmpeg = (pkgs.ffmpeg.override {
    withHeadlessDeps = false;
    withSmallDeps = false;
    withFullDeps = false;
    buildAvcodec = true;
    buildAvformat = true;
    buildAvutil = true;
    buildSwresample = true;
    buildSwscale = true;
    withSafeBitstreamReader = true;
    withGPL = false;
    withVersion3 = false;
  }).overrideAttrs (old: { meta = old.meta // { broken = false; }; });
  media = (pkgs.qt6.qtmultimedia.override { inherit ffmpeg; }).overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ [ "-DFEATURE_ffmpeg=ON" ];
    postPatch = (old.postPatch or "") + ''
      # Windows resolves this spelling; the Linux cross builder is case-sensitive.
      substituteInPlace src/plugins/multimedia/ffmpeg/ffmpeg_pch.h \
        --replace-fail '<D3d11.h>' '<d3d11.h>'
    '';
  });
  app = pkgs.stdenv.mkDerivation {
    pname = "agora-windows-native";
    version = "0.3.0";
    src = pkgs.lib.cleanSource ../native;
    nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.pkg-config pkgs.qt6.wrapQtAppsHook ];
    buildInputs = [ pkgs.qt6.qtbase pkgs.qt6.qtdeclarative media pkgs.openssl ];
    cmakeFlags = [ "-DAGORA_EXPECTED_QT_VERSION=${pkgs.qt6.qtbase.version}" ]
      ++ (pkgs.logosQtCrossCmakeFlags or []);
    dontWrapQtApps = true;
  };
in {
  native = app;
  multimedia = media;
  # MinGW DLLs install in the primary output/bin, not the Unix library output.
  codecs = ffmpeg.out;
  qtVersion = pkgs.qt6.qtbase.version;
}
