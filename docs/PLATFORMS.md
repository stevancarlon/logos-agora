# Desktop platform acceptance

The [0.3.1 alpha](https://github.com/stevancarlon/logos-agora/releases/tag/v0.3.1-alpha.1) publishes Linux x86_64, Windows x86_64, Intel macOS and Apple Silicon macOS kits. Each kit passed installation and actual Basecamp UI/backend loading. Intel/Apple Silicon/Windows additionally passed MP4 and WebM playback. The companion media runtime remains required; these are unsigned testing packages, not a completed production-network release.

Current candidate evidence: [Linux](https://github.com/stevancarlon/logos-agora/actions/runs/40342811322), [Apple Silicon and desktop checks](https://github.com/stevancarlon/logos-agora/actions/runs/40342818168), [Intel Basecamp integration](https://github.com/stevancarlon/logos-agora/actions/runs/40343339261), [Windows archive/upgrade/media checks](https://github.com/stevancarlon/logos-agora/actions/runs/40344924853). The release includes VERIFICATION.json, package hashes and the Windows runtime source/license companion. Physical audio devices, the user's Intel Mac running Sequoia 15.1, and real cross-machine messaging remain unverified.

The notes below describe the earlier development sequence; their pending states are superseded by the current release evidence above.

- Linux: 23 backend and 24 QML checks pass after portability changes. The MP4
  regression also passes without a system MIME database. The development kit
  also passes installation and actual Basecamp UI/backend loading in an isolated
  profile (`artifacts/portable-linux-host-check/result.json`), including corruption
  rejection; this does not constitute a new published release.
- Intel and Apple Silicon macOS: all 23 backend and 24 QML checks pass.
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
- Windows x86_64: all 23 backend and 24 QML checks pass using Qt MinGW.
  The initial MSVC build was replaced to align with Basecamp's MinGW toolchain;
  These standalone tests used Qt 6.9.2 and do not establish host compatibility.
  Basecamp's pinned `logos-nix` Windows package set uses Qt 6.11.1 with Vulkan
  disabled. Actual symbol inspection found missing private QObject constructor
  and Vulkan functions when mixing the official 6.9.2 Multimedia/SQLite plugins
  with Basecamp. The matching Nix/CMake build uses Basecamp's exact package set;
  its first actual host check now passes with no missing non-system imports.
  Agora opens in official Basecamp and renders MP4 frames, pauses, seeks, resumes,
  and stops on navigation. [Windows host check](https://github.com/stevancarlon/logos-agora/actions/runs/38196428403).
  The matching FFmpeg runtime and precompiled archive now pass checksum validation,
  corruption rejection, installation and actual Basecamp MP4 and WebM playback,
  including pause, seek, resume and navigation-stop, in separate disposable profiles.
  [Verified Windows media run](https://github.com/stevancarlon/logos-agora/actions/runs/40334755297),
  using [runtime build 40332849297](https://github.com/stevancarlon/logos-agora/actions/runs/40332849297).
  This is hosted-runner evidence; audio hardware, interactive clean-desktop
  installation and cross-machine exchange remain unverified.

Hosted results: [desktop checks at 7c95957](https://github.com/stevancarlon/logos-agora/actions/runs/40330508080)
pass 23 backend and 24 QML tests per platform. Apple Silicon also passes
archive installation and actual Basecamp MP4 and WebM playback in separate
disposable profiles. [Linux checks](https://github.com/stevancarlon/logos-agora/actions/runs/40330503154) pass.

The LGX packager accepts each target variant and checks the backend binary's
architecture before packaging. Package structure validation does not establish
runtime compatibility. Raw Mac binaries reference Homebrew OpenSSL; the development runtime installer
relocates their dependencies to Basecamp and separately staged media libraries.
The official Basecamp app is unchanged. The Apple Silicon development kit is verified on a hosted runner; it is not yet a published end-user release. The Windows development archive is also verified on a hosted runner. Intel Mac host packaging remains unfinished.

Run `python scripts/build-native.py` with `QMAKE` pointing at Qt 6.9.2 and
`OPENSSL_ROOT_DIR` pointing at the OpenSSL installation when needed. Windows
requires Basecamp’s matching Windows package set (see `nix/windows-agora.nix`); macOS uses the native CPU
architecture. These are development commands, not complete end-user packages.

Linux and Apple Silicon have archive installation and actual Basecamp video evidence. Windows has archive installation and actual host MP4/WebM evidence with the matching FFmpeg runtime. Intel Mac still needs both checks. Every platform needs cross-machine network acceptance; successful native unit tests alone do not prove host compatibility.

The official Basecamp 0.3.2 Mac DMG is Apple Silicon-only. The pinned upstream
source (`f2fae630737bc56ef8c4bb33ce92ae365ba8abb9`) includes `x86_64-darwin`.
The separate Intel host workflow builds its `bin-macos-app`, link gate and smoke
test. The previous runner lost communication during bundling (GitHub runner
infrastructure failure; no compiler failure established). A retry limits build
concurrency and retains a diagnostic log; no successful Intel host is claimed. Never substitute an ARM download for an
Intel-compatible host or claim this host build is an official upstream binary.

The official Delivery 0.3.2 LGX also lacks an Intel Mac variant. A separate pinned
source build initially failed because the Nim C linker omitted Darwin's C++
runtime despite linking BoringSSL/Leopard C++ objects. The Intel workflow now
adds `-lc++` to a copied, pinned source input. Its [development build passed](https://github.com/stevancarlon/logos-agora/actions/runs/38196226650),
but artifact inspection found a `darwin-amd64-dev` variant with Nix store
library dependencies. That package is not suitable for distribution. The
workflow now builds `lgx-portable` and checks the portable variant, each dylib's
Intel architecture and absence of Nix store load paths. Actual installation
and MP4/WebM checks are prepared in `intel-host-check.yml`; they require
successful portable Basecamp and Delivery run IDs. Loading these together
remains unverified.

The merged default branch at `841d229` passes [Linux checks](https://github.com/stevancarlon/logos-agora/actions/runs/40337478339) and [desktop checks](https://github.com/stevancarlon/logos-agora/actions/runs/40337478401). A separate [Windows upgrade check](https://github.com/stevancarlon/logos-agora/actions/runs/40335644246) deliberately replaces a staged codec with stale bytes, reinstalls the runtime, verifies its restored hash, and repeats actual Basecamp MP4/WebM playback. This verifies replacement of existing runtime dependencies as well as fresh installation.
