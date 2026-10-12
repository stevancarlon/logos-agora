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
- The matching Qt 6.9.2 distribution with Multimedia. This is currently a separate
  download; the kit does not include Qt. For example, install `aqtinstall==3.3.0`
  in a Python virtual environment, then use the corresponding command:

```sh
python -m aqt install-qt mac desktop 6.9.2 clang_64 -O "$HOME/Qt" --modules qtmultimedia --archives qtbase qtdeclarative qtmultimedia
```

Windows runtime packaging is being corrected to match Basecamp’s pinned Qt
6.11.1 build. The official Qt 6.9.2 Windows SDK is not a compatible substitute.

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

Windows kits are not ready for installation. The native test build and host
runtime used different Qt versions/configurations; the new matching toolchain
must pass actual Basecamp loading and video checks before commands are published.
The planned launcher uses a separate runtime and keeps Basecamp unchanged.

## Profile and runtime locations

`--user-dir`, `--runtime-dir` and `--launcher` override installation paths. Use a
separate `--user-dir` when evaluating a candidate. A kit for a different CPU or
OS is rejected before installation. Checksums detect changed files but are not
publisher signatures: obtain a kit and its expected archive hash from a trusted
release source.

The public Linux instructions remain in [RELEASE.md](RELEASE.md). Development
video tests use marked disposable profiles; those probes and synthetic posts are
not included in the release interface.
