# Isolated attachment examples

Original synthetic assets for the AgoraExamples profile only:

- workshop-diagram.png: programmatically drawn local-first workshop diagram.
- playback-test.mp4: six-second FFmpeg testsrc2 clip (640x360, H.264).
- workshop-plan.pdf: one-page synthetic agenda, generated with ReportLab.

No real event or community activity is represented. No third-party photos are used.

Seed only the dedicated profile with `LOGOS_FORUM_DATA_DIR=$HOME/.local/share/Logos/AgoraExamples/module_data/logos_forum QT_QPA_PLATFORM=offscreen build/qt6.9.2-preview/forum-preview --seed-media --media-dir "$PWD/design/agora/demo-media"`. This command is idempotent for the example thread. The app must be closed before installing its updated module. Keep publishing disabled in the examples profile.
