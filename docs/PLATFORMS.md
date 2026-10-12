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
  The precompiled archive also passes checksum/corruption rejection, installation
  without compilation, and the same host/video checks after the extracted kit is
  deleted. [Archive installation run](https://github.com/stevancarlon/logos-agora/actions/runs/38195928937/job/114638526963).
  This uses a hosted runner with Qt SDK and Apple command-line tools installed;
  audio hardware, interactive desktop installation and cross-machine exchange remain open.
- Windows x86_64: all 22 backend and 24 QML checks pass using Qt MinGW.
  The initial MSVC build was replaced to align with Basecamp's MinGW toolchain;
  These standalone tests used Qt 6.9.2 and do not establish host compatibility.
  Basecamp's pinned `logos-nix` Windows package set uses Qt 6.11.1 with Vulkan
  disabled. Actual symbol inspection found missing private QObject constructor
  and Vulkan functions when mixing the official 6.9.2 Multimedia/SQLite plugins
  with Basecamp. The matching Nix/CMake build uses Basecamp's exact package set;
  its runtime result is pending.

Hosted results: [desktop checks at 417277d](https://github.com/stevancarlon/logos-agora/actions/runs/38192205277)
and [Linux checks](https://github.com/stevancarlon/logos-agora/actions/runs/38192205300).

The LGX packager accepts each target variant and checks the backend binary's
architecture before packaging. Package structure validation does not establish
runtime compatibility. Raw Mac binaries reference Homebrew OpenSSL; the development runtime installer
relocates their dependencies to Basecamp and separately staged media libraries.
The official Basecamp app is unchanged. The Apple Silicon development kit is verified on a hosted runner; it is not yet a published end-user release. Intel Mac and Windows kits remain unfinished.

Run `python scripts/build-native.py` with `QMAKE` pointing at Qt 6.9.2 and
`OPENSSL_ROOT_DIR` pointing at the OpenSSL installation when needed. Windows
requires Basecamp’s matching Windows package set (see `nix/windows-agora.nix`); macOS uses the native CPU
architecture. These are development commands, not complete end-user packages.

Linux and Apple Silicon have archive installation and actual Basecamp video evidence. Intel Mac and Windows still need those checks. Every platform needs cross-machine network acceptance; successful native unit tests alone do not prove host compatibility.

The official Basecamp 0.3.2 Mac DMG is Apple Silicon-only. The pinned upstream
source (`f2fae630737bc56ef8c4bb33ce92ae365ba8abb9`) includes `x86_64-darwin`.
The separate Intel host workflow builds its `bin-macos-app`, link gate and smoke
test; its result is not yet verified. Never substitute an ARM download for an
Intel-compatible host or claim this host build is an official upstream binary.

The official Delivery 0.3.2 LGX also lacks an Intel Mac variant. A separate pinned
source build initially failed because the Nim C linker omitted Darwin's C++
runtime despite linking BoringSSL/Leopard C++ objects. The Intel workflow now
adds `-lc++` to a copied, pinned source input and is being rechecked; no Intel
host/Delivery runtime result is claimed yet.
