# Prebuilt Linux installation

The release kit supplies compiled Agora code, the pixel renderer and a verified
unsigned LGX. It does not contain a user database, signing keys, or sample posts.
This is currently a companion-runtime installation, not an LGX-only installation
on stock Basecamp. The unsigned alpha is served by the community catalog. Publisher signing and catalog UI installation acceptance remain open.

Requirements: Linux x86_64, Python 3 with venv support, OpenSSL 3, a working
Basecamp 0.3.2 AppImage, and Qt 6.9.2 with Multimedia. Install Delivery 0.3.2 in
Basecamp's module manager before connecting. Basecamp/AppImage system dependencies
must already be satisfied. On Ubuntu 24.04, include `libopengl0`, `libharfbuzz0b`, `libpulse0` and `libasound2t64`; these are needed even with the matching Qt runtime. The complete isolated test environment is listed in `scripts/containers/ubuntu-runtime.Dockerfile` in the source repository. Close Basecamp before updating an existing runtime.

From the extracted release directory, validate the files:

```sh
python3 scripts/install-release.py --verify-only
```

Checksums detect accidental corruption; they do not authenticate the publisher.
Obtain releases from [the project's release page](https://github.com/stevancarlon/logos-agora/releases).

If the matching Qt runtime is not already installed, download official Qt binaries
using aqtinstall (no Agora compilation is necessary):

```sh
python3 -m venv .qt-installer
.qt-installer/bin/pip install aqtinstall==3.3.0
.qt-installer/bin/python -m aqt install-qt linux desktop 6.9.2 linux_gcc_64 -O "$HOME/Qt" --modules qtmultimedia --archives qtbase qtdeclarative qtmultimedia icu
```

Install, supplying the actual Basecamp path:

```sh
python3 scripts/install-release.py --qt "$HOME/Qt/6.9.2/gcc_64" --appimage "$HOME/Applications/LogosBasecamp-0.3.2-x86_64.AppImage"
"$HOME/Applications/LogosBasecamp-Agora" --uri=basecamp://app/logos_forum
```

The installer preserves the Basecamp AppImage, installs the extra media runtime
separately, and updates an existing desktop shortcut with a backup. User data is
preserved. `--user-dir`, `--runtime-dir`, `--launcher` and `--no-desktop` support
isolated installations. Set `LOGOS_USER_DIR` and `LOGOS_FORUM_DATA_DIR` when running
an isolated profile, as documented in README.md.

Shared media requires each user to configure their own local Logos Storage node; otherwise attachments remain device-local. See STORAGE.md in the source documentation.
The Qt runtime is downloaded from Qt rather than redistributed in this kit;
upstream licensing references are written to the installed runtime's README.
