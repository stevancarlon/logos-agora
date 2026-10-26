# Install Agora alpha (Linux x86_64)

Download the [0.3 alpha release](https://github.com/stevancarlon/logos-agora/releases/tag/v0.3.0-alpha.1), verify its archive checksum, and follow [the precompiled installation guide](docs/RELEASE.md). The kit includes compiled Agora code; the matching Qt media companion is still required. Close Basecamp before updating. Installers preserve user databases and signing keys.

This is an unsigned testing release for Basecamp 0.3.2 and Qt 6.9.2. Shared attachments require a local Logos Storage node; see [Storage setup](docs/STORAGE.md). Without one, attachments remain device-local. Existing local-only discussions remain local.

## Community catalog

Add `https://raw.githubusercontent.com/stevancarlon/logos-agora/main/logos-repo.json` as a custom Basecamp repository. The catalog serves the LGX package; it does not install the media companion. This is a community catalog, not an official or trusted-signed catalog.

In Basecamp, open **Package Manager → Manage Repositories**, paste that URL and
select **Add**. Return to Package Manager, select **Reload**, search for **forum**
(the host searches the module identifier), and install **Agora**. Review the
listed dependencies, then open Agora from the sidebar. Install the companion
runtime first using the precompiled guide above.

This path passed on 26 October 2026 in a disposable Ubuntu 24.04/Xvfb desktop
running the official Basecamp 0.3.2 AppImage with the companion runtime. The GUI
installed the published 0.3.0 package, and Agora's UI and SQLite backend loaded.
The current official catalog selected Delivery 0.4.0 plus its optional modules;
network interoperability with that version is not established by this installation
check. The existing network acceptance evidence uses pinned Delivery 0.3.2.


## Verification and limits

The source passes native tests on GitHub's default branch. Private loopback Basecamp exchange, restart retry, Store recovery and local Storage transfers are covered by the acceptance checks. A sent marker means transport acknowledgement, not proof every peer received a post.

Cross-machine messaging, public-network retention, full desktop installation on a separate clean OS and authentic community adoption remain unverified. See [acceptance requirements](docs/ACCEPTANCE.md) before treating this alpha as a production release or completed prize submission.
