# Install Agora alpha

Download the [latest alpha release](https://github.com/stevancarlon/logos-agora/releases), choose the kit for your CPU/OS, and verify its archive checksum. Linux instructions are in [the precompiled installation guide](docs/RELEASE.md); Mac/Windows instructions are in [the desktop guide](docs/DESKTOP-INSTALL.md). Intel Mac users should follow the release's [Intel quickstart](https://github.com/stevancarlon/logos-agora/releases/download/v0.3.1-alpha.1/INTEL-MAC-QUICKSTART.txt). The kit includes compiled Agora code; the matching Qt media companion is still required. Close Basecamp before updating. Installers preserve user databases and signing keys.

This is an unsigned testing release for Basecamp 0.3.2. Linux/macOS use Qt 6.9.2; Windows needs the release's matching Qt 6.11.1 runtime and source/license companion. Shared attachments require a local Logos Storage node; see [Storage setup](docs/STORAGE.md). Without one, attachments remain device-local. Existing local-only discussions remain local.

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
this installation check alone does not establish network interoperability. A
separate test of the current Agora development build with Delivery 0.4.0 passes
signed and anonymous thread/reply exchange, offline restart and Store recovery
between independent Basecamp processes over a private loopback relay. This does
not verify cross-machine connectivity or the published alpha's network behavior
with 0.4.0. Earlier network evidence uses pinned Delivery 0.3.2.


## Verification and limits

The source passes native tests on GitHub's default branch. Private loopback Basecamp exchange, restart retry, Store recovery and local Storage transfers are covered by the acceptance checks. A sent marker means transport acknowledgement, not proof every peer received a post.

Public Delivery receipt is verified between separate profiles on one Linux host; see [network setup and evidence](docs/NETWORK.md). Cross-machine messaging, public Storage retention and authentic community adoption remain unverified. See [acceptance requirements](docs/ACCEPTANCE.md) before treating this alpha as a production release or completed prize submission.
