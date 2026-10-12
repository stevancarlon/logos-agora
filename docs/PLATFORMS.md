# Desktop platform acceptance

The supported-platform target is Linux x86_64, Windows x86_64, Intel macOS and
Apple Silicon macOS. Only the Linux alpha is currently published and verified in
Basecamp. Cross-platform development is on `codex/desktop-platforms` / PR #3.

- Linux: 22 backend and 24 QML checks pass after portability changes. The MP4
  regression also passes without a system MIME database.
- Intel and Apple Silicon macOS: first builds compile successfully, but their
  video-import test exposed Qt's bundled MIME database identifying MP4 as
  QuickTime. The container-brand fix passes all 22 backend checks on Apple Silicon. UI checks exposed native-style customization restrictions; components now explicitly use Qt Basic controls, awaiting hosted UI verification.
- Windows: OpenSSL dependency compilation completed; application checks are in
  progress. The initial MSVC build does not match Basecamp's MinGW ABI and will not be packaged. The workflow now uses Qt MinGW and the matching GCC toolchain.

Run `python scripts/build-native.py` with `QMAKE` pointing at Qt 6.9.2 and
`OPENSSL_ROOT_DIR` pointing at the OpenSSL installation when needed. Windows
requires the matching MinGW toolchain; macOS uses the native CPU
architecture. These are development commands, not complete end-user packages.

Every platform still needs its appropriate release kit, dependency/runtime
installation, and actual Basecamp load/media/network tests. Successful native
unit tests alone do not prove host compatibility.

The official Basecamp 0.3.2 Mac DMG is Apple Silicon-only. The pinned upstream
source (`f2fae630737bc56ef8c4bb33ce92ae365ba8abb9`) includes `x86_64-darwin`.
The separate Intel host workflow builds its `bin-macos-app`, link gate and smoke
test; its result is not yet verified. Never substitute an ARM download for an
Intel-compatible host or claim this host build is an official upstream binary.
