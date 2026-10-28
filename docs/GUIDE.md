# Agora usage and development

Detailed setup, everyday use, identity and media notes. For prebuilt downloads, start with [installation](../INSTALL.md).

## Open the installed app

Basecamp is installed at `~/Applications/LogosBasecamp-0.3.2-x86_64.AppImage`. Agora is installed in its local plugins folder. Launch with the multimedia-enabled wrapper (also used by the desktop shortcut), then open Agora:

```sh
~/Applications/LogosBasecamp-Agora --uri=basecamp://app/logos_forum
```

Use the header’s **/all/** and board links to browse. The feed places its sort dropdown on the left and **New thread** on the right; the board dropdown appears only on narrow windows where the header board links are hidden. Each thread shows its opening text, latest reply preview when available, and a **Reply** action that opens its composer. Desktop search lives in the header; Ctrl+F focuses search. The profile icon opens identity/avatar settings. Saved threads and network settings are available in the profile dialog. Narrow windows retain board and sort selectors. Pending and failed delivery states stay on posts; there is no sidebar or Outbox tab.

Feeds load 30 discussions per page and open discussions load 50 replies per page. Previous/next controls appear when needed; search covers the whole local archive.

Create a thread, reply, quote a post, switch boards, search, bookmark or change identity. Text-only posts enter the durable outbox. With a local Logos Storage node configured, new attachments upload to Storage and their signed references are queued with the post. Without that configuration, attachment posts and their replies stay local. In **Network**, connect to an already-running Delivery node, or explicitly start one. Optionally enable **Connect when Agora opens** to reconnect automatically; it is off by default. The app subscribes to its content topic and sends one queued item at a time. A matching Delivery acknowledgement changes it to sent. A sent label does not guarantee receipt by every peer.

Offline threads, drafts, identities and outbox entries remain available after restart. **Load history** requests at most 50 messages from a Store peer multiaddress you provide; its cursor is persisted. No public peer or centralized API is hardcoded.

## Build and test

Linux x86_64 requires a C++17 compiler, make, Python 3, OpenSSL 3 development headers, and Qt **6.9.2** with Core, GUI, Quick, QML, SQL/SQLite, Multimedia and QuickTest. Match the Qt version shipped by Basecamp; a plugin compiled against system Qt 6.11 cannot safely be loaded into Qt 6.9.

```sh
python3 -m venv .venv
.venv/bin/pip install aqtinstall==3.3.0
.venv/bin/python -m aqt install-qt linux desktop 6.9.2 linux_gcc_64 -O "$HOME/Qt" --modules qtmultimedia --archives qtbase qtdeclarative qtmultimedia icu
QMAKE="$HOME/Qt/6.9.2/gcc_64/bin/qmake" scripts/build-native.sh
python3 scripts/install-media-runtime.py --qt "$HOME/Qt/6.9.2/gcc_64"
python3 scripts/install-basecamp.py
```

Restart Basecamp after installing an update. Installation does not touch user data. The backend binary is `native/forum/libforum_backend.so`; the installer renames it to `forum_backend.so` as required by the manifest.

`build/qt6.9.2-preview/forum-preview` runs the native interface standalone; Delivery is only available inside Basecamp. For UI development with another Qt version, use `ALLOW_OTHER_QT=1` and do not install that binary in Basecamp. `--screenshot artifacts/forum-desktop.png` uses temporary, clearly labeled examples and never publishes them.

The build script runs backend tests (signatures, tampering, deduplication, separate database exchange, restart recovery, history validation) and QML workflow tests (compose/reply/quote, identities, search, narrow layout, delivery callback races/failures). Hosted [Linux checks](https://github.com/stevancarlon/logos-agora/actions/runs/40337478339) and [Windows/Intel Mac/Apple Silicon checks](https://github.com/stevancarlon/logos-agora/actions/runs/40337478401) pass 23 backend and 24 QML checks per platform. See [desktop platform acceptance](PLATFORMS.md) for the remaining host integration and packaging work.

## Package

Build the official [logos-package CLI](https://github.com/logos-co/logos-package) and put `lgx` on PATH, then:

```sh
python3 scripts/package-native.py --lgx /absolute/path/to/lgx
```

This produces `artifacts/logos_forum-0.3.1-linux-amd64.lgx` and runs `lgx verify`. It is an **unsigned local development package**, not a trusted catalog publication. It includes original-code licenses and an original 256×256 icon. Windows x86_64 and Apple Silicon development archives also pass installation and actual Basecamp MP4/WebM playback checks. Intel Mac archive installation and Basecamp MP4/WebM playback also pass. All four alpha kits are published; see [platform evidence](PLATFORMS.md) before choosing a package. Package CLI revision used locally: `c25a1167578aef5cbd9a9b6f822ffe2ae4fd6a89`.

The header profile icon opens **Profile**. You can upload, replace or remove a PNG/JPEG avatar (up to 8 MB and 4096 pixels per side). It is cropped to a square, resized and saved locally for that identity. Avatars are not included in published posts.

## Data and identities

Basecamp data: `~/.local/share/Logos/LogosBasecamp/module_data/logos_forum/forum.sqlite`. `LOGOS_USER_DIR` selects another Basecamp profile; `LOGOS_FORUM_DATA_DIR` overrides the database directory. SQLite uses WAL, transactions, parameterized queries, a busy timeout, and owner-only directory/file permissions. Close the app before copying the entire data directory for a backup; keep it private because it contains signing keys. Data and keys are **not encrypted at rest**.

Alias and UID posts are signed with Ed25519. Alias text is not unique: the public key defines the identity. Anonymous posts omit the stable public key and signature. Optional rotation creates a new signing identity after each new thread. Public posts are not end-to-end encrypted. Anonymous display, key rotation and requested mix routing do not constitute a verified network-anonymity guarantee.

## Attachments and peer media

Threads and replies accept up to four PNG/JPEG images, MP4/WebM videos or PDFs, each at most 64 MB (images at most 24 megapixels). Files are copied into the profile's private `attachments/` directory, with metadata and thumbnail data in SQLite. Back up the whole data directory, not just the database.

Images have inline thumbnails. Video and PDF posters use optional `ffmpeg` and `pdftoppm` helpers to make thumbnails; without these tools they display a file-type placeholder. Videos play directly in the discussion. Compact play/pause, seek and volume controls overlay the picture, fade out while playing, and reappear on hover, pause or keyboard focus. Download is a small overlay icon; video filename/size footers are omitted. PDF/image Open launches the system viewer (`xdg-open`, macOS `open`, or Windows Explorer). Download saves a separate copy and does not overwrite existing files. Removed draft attachments remain stored locally for now.

To share new attachments, open Network → Advanced and save your own node's loopback API URL, for example `http://127.0.0.1:8080/api/storage/v1`. Posting uploads files sequentially to Logos Storage; a signed v2 message carries the CID, name, MIME type, exact byte count and SHA-256. Readers choose **Fetch** to retrieve each file through their own local Storage node. The app checks the signed size, hash and MIME before displaying or opening it. Downloads are bounded at 64 MB; redirects and remote HTTP gateways are rejected. Uploads publish the original file bytes, including any embedded metadata.

Without a Storage connection, attachments remain local-only; existing local conversations are not silently published when a connection is added. Shared attachment support requires updated Agora clients. The examples profile (`AgoraExamples`) contains synthetic media and disables Delivery publishing; do not configure a Storage endpoint there. See [STORAGE.md](STORAGE.md) for node setup and the current testing scope.

## Embedded video runtime

The multimedia launcher keeps the official Basecamp AppImage intact and selects an additional local Qt 6.9.2 runtime. `scripts/install-media-runtime.py` installs it and updates the desktop shortcut (preserving its previous contents). The LGX depends on this companion runtime; it is not sufficient by itself on stock Basecamp 0.3.2. Standalone preview commands need `QML_IMPORT_PATH="$PWD/build/qt6.9.2-media/qml"`.

Video decoding and audio run in the out-of-process native backend. The player accepts a stored video attachment ID, never an arbitrary media URL. QML receives only state and bounded RGBA frames, displayed by the small `Agora.Media` renderer in the explicitly installed runtime. The renderer has no filesystem or networking API. Basecamp's URL/network sandbox is unchanged. Playback is limited to a 640-pixel maximum dimension, with frames polled at most 25 times per second; original attachment files and exported copies are unchanged. One video plays at a time, and leaving/destroying its discussion stops playback.

The default Qt/FFmpeg codecs are used. Unsupported media shows an inline error. Video sharing uses signed protocol v2 references and Logos Storage; inline playback remains within the app.

## Public network

Follow [NETWORK.md](NETWORK.md) for the current Delivery/RLN dependencies and
testnet funding steps. Earlier network examples do not guarantee compatibility
with the current public testnet.
