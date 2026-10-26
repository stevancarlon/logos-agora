# Desktop installation kits — development status

Only the Linux alpha is currently published. Mac and Windows kits are development
artifacts, not a supported public release. See [PLATFORMS.md](PLATFORMS.md) for
actual host results. Intel Mac additionally needs verified native Basecamp and
Delivery builds; the official ARM downloads cannot be used as Intel binaries.

Each kit contains the compiled Agora backend, renderer, QML interface and
installation scripts. Installation does not compile Agora and does not replace
its SQLite database or identities. Close Basecamp before updating a kit.

## Prerequisites

- Basecamp 0.3.2 and the official Delivery 0.3.2 module installed through its package
  manager. The companion runtime does not supply Delivery.
- Python 3.12 or newer to run the installer.
- On macOS, Apple Command Line Tools providing `install_name_tool` and `codesign`
  for dependency relocation and local signatures. Agora itself is not compiled.
- On macOS, the matching Qt 6.9.2 distribution with Multimedia. This is currently a separate
  download; the kit does not include Qt. For example, install `aqtinstall==3.3.0`
  in a Python virtual environment, then use the corresponding command:

```sh
python -m aqt install-qt mac desktop 6.9.2 clang_64 -O "$HOME/Qt" --modules qtmultimedia --archives qtbase qtdeclarative qtmultimedia
```

Windows requires the matching Qt 6.11.1 companion artifact built by `windows-matched.yml`. The official Qt 6.9.2 Windows SDK is not a compatible substitute.

## macOS

Extract the kit for the correct CPU, enter its directory, then:

```sh
python3 scripts/install-release.py --verify-only
python3 scripts/install-release.py --qt "$HOME/Qt/6.9.2/macos" --app /Applications/LogosBasecamp.app
```

The installer checks file hashes and the kit's CPU target, installs Agora into
Basecamp's user profile, stages missing media libraries, and creates
`~/Applications/Agora.command`. Launch that file, then open Agora in Basecamp.
The original Basecamp application bundle remains unchanged. Moving Basecamp or
its companion runtime later requires rerunning the installer so library paths
are updated. Local ad-hoc library signatures do not provide publisher identity
or notarization.

## Windows

The development archive has passed installation, corruption rejection and actual
Basecamp MP4 and WebM playback on a Windows runner ([verified run](https://github.com/stevancarlon/logos-agora/actions/runs/40334755297)).
It is not yet a published release. The matching runtime includes FFmpeg;
audio hardware and cross-machine exchange have not yet been verified.

Download the `agora-kit-windows-amd64-development` artifact from that run and the
`agora-windows-matching-qt` artifact from its pinned [runtime build](https://github.com/stevancarlon/logos-agora/actions/runs/40332849297).
Extract both ZIP files and their `.tar.gz` archives. Keep the runtime's
`windows-matched/qt-version.txt` beside its `qt` directory. With official
Basecamp 0.3.2 and Delivery installed, run from the extracted Agora kit in PowerShell:

```powershell
python scripts/install-release.py --verify-only
python scripts/install-release.py --qt "C:\path\to\windows-matched\qt" --host-bin "C:\path\to\Basecamp\bin"
```

Replace both paths with the actual extracted runtime and installed Basecamp paths.
The installer stages missing DLLs separately and leaves Basecamp's files unchanged.
Launch `%LOCALAPPDATA%\Programs\Agora\Launch-Agora.cmd`, then open Agora.
Keep the same matching runtime and archive together when sharing this development
candidate; using an arbitrary Qt download can produce loader errors.

## Profile and runtime locations

`--user-dir`, `--runtime-dir` and `--launcher` override installation paths. Use a
separate `--user-dir` when evaluating a candidate. A kit for a different CPU or
OS is rejected before installation. Checksums detect changed files but are not
publisher signatures: obtain a kit and its expected archive hash from a trusted
release source.

The public Linux instructions remain in [RELEASE.md](RELEASE.md). Development
video tests use marked disposable profiles; those probes and synthetic posts are
not included in the release interface.
