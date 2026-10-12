# Install Agora alpha (Linux x86_64)

Download the [0.3 alpha release](https://github.com/stevancarlon/logos-agora/releases/tag/v0.3.0-alpha.1), verify its archive checksum, and follow [the precompiled installation guide](docs/RELEASE.md). The kit includes compiled Agora code; the matching Qt media companion is still required. Close Basecamp before updating. Installers preserve user databases and signing keys.

This is an unsigned testing release for Basecamp 0.3.2 and Qt 6.9.2. Shared attachments require a local Logos Storage node; see [Storage setup](docs/STORAGE.md). Without one, attachments remain device-local. Existing local-only discussions remain local.

## Community catalog

Add `https://raw.githubusercontent.com/stevancarlon/logos-agora/main/logos-repo.json` as a custom Basecamp repository. The catalog serves the LGX package; it does not install the media companion. This is a community catalog, not an official or trusted-signed catalog.

## Verification and limits

The source passes native tests on GitHub's default branch. Private loopback Basecamp exchange, restart retry, Store recovery and local Storage transfers are covered by the acceptance checks. A sent marker means transport acknowledgement, not proof every peer received a post.

Cross-machine messaging, public-network retention, full desktop installation on a separate clean OS and authentic community adoption remain unverified. See [acceptance requirements](docs/ACCEPTANCE.md) before treating this alpha as a production release or completed prize submission.
