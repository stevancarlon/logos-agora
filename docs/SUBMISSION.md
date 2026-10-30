# Agora — submission materials

The source, release, presentation and filled solution are prepared. The author has chosen not to pursue organic community participation or testnet 0.4 verification as part of this preparation. Both remain explicitly unverified; this is not an organizer waiver or a claim that every prize criterion is fulfilled.

- [Source](https://github.com/stevancarlon/logos-agora)
- [Updated alpha release](https://github.com/stevancarlon/logos-agora/releases/tag/v0.3.5-alpha.1)
- [Narrated presentation](https://github.com/stevancarlon/logos-agora/releases/download/v0.3.3-alpha.1/agora-presentation.mp4)
- [Filled solution](submission/LP-0026.md)
- [Installation](../INSTALL.md) and [community catalog](https://raw.githubusercontent.com/stevancarlon/logos-agora/main/logos-repo.json)
- [FURPS assessment](FURPS.md) and [network evidence](evidence/NETWORK-VERIFICATION-20261030.md)

Agora is a native C++/Qt/QML forum with SQLite persistence and no centralized application backend. Delivery carries signed posts and history; Storage carries attachment bytes. Original code is MIT OR Apache-2.0.

## Verification scope

26 backend and 67 QML checks pass locally. Hosted native and matching-Windows builds passed for the attachment-fix code at `d4cbade`; release metadata is updated to 0.3.5. Current default-branch checks are visible in [Actions](https://github.com/stevancarlon/logos-agora/actions).

Native PNG/MP4/PDF upload, public retrieval and exact-byte export pass through public discovery/relays with fresh readers on one computer, including after installation and provider restart. The corrected independent GitHub-hosted reader now passes all three original fixture CIDs with exact size/hash checks ([run](https://github.com/stevancarlon/logos-agora/actions/runs/41111993615)). See [cross-machine Storage verification](evidence/PUBLIC-STORAGE-20261030.md). Earlier failures are retained for comparison. This does not claim cross-machine Delivery/Store messaging.

No prize acceptance declaration or external solution pull request has been submitted. The filled solution reports the tested behavior and remaining limitations so it can be reviewed without overstating readiness.
