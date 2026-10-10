#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
QMAKE=${QMAKE:-qmake6}
if [[ "$($QMAKE -query QT_VERSION)" != "6.9.2" && "${ALLOW_OTHER_QT:-0}" != 1 ]]; then
  echo 'Basecamp 0.3.2 requires Qt 6.9.2. Set QMAKE to that qmake. ALLOW_OTHER_QT=1 is for standalone development only.' >&2
  exit 1
fi
qt_version=$($QMAKE -query QT_VERSION)
for target in media backend preview tests ui-tests; do
  case "$target" in
    media) project=media-renderer/media.pro;;
    backend) project=backend/forum.pro;;
    preview) project=preview/preview.pro;;
    tests) project=tests/tests.pro;;
    ui-tests) project=tests/ui.pro;;
  esac
  mkdir -p "build/qt$qt_version-$target"
  (cd "build/qt$qt_version-$target"; "$QMAKE" "../../native/$project"; make -j"${JOBS:-4}")
done
"build/qt$qt_version-tests/backend_tests" -nocrashhandler
QML_IMPORT_PATH="$PWD/build/qt$qt_version-media/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software "build/qt$qt_version-ui-tests/forum-ui-tests" -input native/tests/qml -nocrashhandler
