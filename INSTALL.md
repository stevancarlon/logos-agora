# Install Agora alpha (Linux x86_64)

This is an unsigned testing release for Basecamp 0.3.2 / Qt 6.9.2. Live cross-computer Delivery and Store recovery are not yet verified. Attachments remain device-local. Back up existing Agora data before testing; installers preserve the database and signing keys.

1. Install the official Logos Basecamp 0.3.2 Linux x86_64 AppImage at `~/Applications/LogosBasecamp-0.3.2-x86_64.AppImage`. Install Delivery from the official Basecamp catalog.
2. Download `agora-0.2.0-alpha.1-linux-amd64.tar.gz` and `SHA256SUMS` from this release. Verify the archive with `sha256sum --ignore-missing -c SHA256SUMS`, then extract it and open a terminal in the extracted directory.
3. Obtain the matching Qt runtime (skip the download if Qt 6.9.2 with Multimedia is already installed):

```sh
python3 -m venv .runtime-tools
.runtime-tools/bin/pip install aqtinstall==3.3.0
.runtime-tools/bin/python -m aqt install-qt linux desktop 6.9.2 linux_gcc_64 -O "$HOME/Qt" --modules qtmultimedia --archives qtbase qtdeclarative qtmultimedia icu
```

4. Close Basecamp, install the prebuilt app and its media companion, then open Agora:

```sh
python3 scripts/install-media-runtime.py --qt "$HOME/Qt/6.9.2/gcc_64"
python3 scripts/install-basecamp.py
"$HOME/Applications/LogosBasecamp-Agora" --uri=basecamp://app/logos_forum
```

No compilation or test tokens are required. Linux must provide OpenSSL 3, a compatible C++ runtime, and the normal Basecamp desktop dependencies. `ffmpeg` and `pdftoppm` are optional thumbnail helpers.

## Catalog

Add `https://raw.githubusercontent.com/stevancarlon/logos-agora/main/logos-repo.json` as a custom Basecamp repository. This installs the app package; the media companion setup above is still required for this release. It is a community catalog, not an official or trusted-signed catalog.

## First network test

In the footer open Network. Connect to an already running Delivery node or explicitly start one. Use two separate machines to test a text-only topic and reply. A sent marker is transport acknowledgement, not proof of receipt by the other user. Offline history needs a Store peer multiaddress supplied in Network. This release has no verified shared community service or live peer-exchange claim.
