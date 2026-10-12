# Desktop platform acceptance

The supported-platform target is Linux x86_64, Windows x86_64, Intel macOS and
Apple Silicon macOS. Only the Linux alpha is currently published. Linux and
Apple Silicon development builds have passed actual Basecamp host checks. Cross-platform development is on `codex/desktop-platforms` / PR #3.

- Linux: 22 backend and 24 QML checks pass after portability changes. The MP4
  regression also passes without a system MIME database. The development kit
  also passes installation and actual Basecamp UI/backend loading in an isolated
  profile (`artifacts/portable-linux-host-check/result.json`), including corruption
  rejection; this does not constitute a new published release.
- Intel and Apple Silicon macOS: all 22 backend and 24 QML checks pass.
  MP4 container detection handles Qt's bundled MIME database; explicit Qt Basic
  controls preserve the custom interface across native platforms.
- Apple Silicon host: the official Basecamp 0.3.2 app loads Agora with a separately
  staged runtime. An isolated-profile probe renders video frames and verifies
  pause, seek, resume and stopping on navigation. [Host run](https://github.com/stevancarlon/logos-agora/actions/runs/38193876499/job/114632217710).
  Audio hardware, full desktop installation and cross-machine exchange remain open.
- Windows x86_64: all 22 backend and 24 QML checks pass using Qt MinGW.
  The initial MSVC build was replaced to align with Basecamp's MinGW toolchain;
  actual host ABI compatibility still requires verification.

Hosted results: [desktop checks at 417277d](https://github.com/stevancarlon/logos-agora/actions/runs/38192205277)
and [Linux checks](https://github.com/stevancarlon/logos-agora/actions/runs/38192205300).

The LGX packager accepts each target variant and checks the backend binary's
architecture before packaging. Package structure validation does not establish
runtime compatibility. Raw Mac binaries reference Homebrew OpenSSL; the development runtime installer
relocates their dependencies to Basecamp and separately staged media libraries.
The official Basecamp app is unchanged. End-user release kits remain unfinished.

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

The official Delivery 0.3.2 LGX also lacks an Intel Mac variant. A separate pinned
source build is running; no Intel host/Delivery runtime result is claimed yet.
