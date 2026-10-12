# Current acceptance evidence — 2026-10-11

- Matching Qt 6.9.2 build: 19 backend tests and 22 QML tests pass, zero failures.
- Actual Basecamp production node startup/subscription passes after correcting the
  unsupported network preset. No messages are published by this startup check.
- Three independent Basecamp processes, each with a separate working directory,
  forum database and Delivery Store database, pass private loopback relay tests:
  queued post survives process shutdown, restart delivers the same ID, receiver
  persists it and sends a reply, unsubscribed third process recovers both via Store.
  All three forum databases contain exactly the same two IDs, without duplicates.
  Evidence: `artifacts/network-restart/result.json` and neighboring process logs.
- Extracted precompiled release installs into an isolated profile/runtime and loads
  its actual GUI and backend in the original Basecamp AppImage. Inherited Qt runtime
  overrides are cleared; no Agora compilation occurs. Corrupted-kit verification
  fails before install. Evidence: `artifacts/release-check/result.json`.
- Official LGX validator passes; package remains unsigned. CI now builds a complete
  release kit with the pinned official package tool, but has not run on GitHub.

These checks do not prove clean-OS installation, cross-machine/public mix routing,
public-network media availability, catalog publication, green hosted CI or organic adoption.
Reproduction commands and remaining gates are in [ACCEPTANCE.md](ACCEPTANCE.md).

## Media acceptance — 0.3.0

Two independent local Logos Storage nodes transfer PNG/MP4/PDF. Native backend
verification checks exact bytes, SHA-256 and MIME; corrupted downloads are rejected.
The Basecamp bridge integration separately uploads an MP4, survives offline restart,
exchanges signed v2 references, fetches media in the recipient and recovers history.
See `artifacts/storage-release-candidate/result.json` and `docs/STORAGE.md`.
Storage nodes still require manual local configuration; these are same-machine
private-network checks, not evidence of public retention or adoption.

## Intake and identity regression checks

The updated candidate passes 19 backend and 22 QML checks. Live intake has a
240-message burst budget with four messages/second refill, a 32-call bridge limit
and coalesced single-flight snapshots. The test deliberately exhausts the live
budget and still recovers a valid message via Store without losing its cursor.

`artifacts/network-anonymous-verified/result.json` verifies anonymous-display
threads/replies, restart, Store recovery and absence of author/public-key/signature
fields in all three independent databases. This is not network-anonymity evidence.
`artifacts/storage-intake-check/result.json` revalidates signed alias messages and
media transfers through the actual Basecamp bridge and two real local Storage nodes.
`artifacts/release-intake-check/result.json` verifies isolated precompiled installation.

## Historical checks

### Local verification — 2026-10-08

Environment: Linux x86_64, Basecamp 0.3.2 AppImage, matching Qt 6.9.2 development SDK, OpenSSL 3, SQLite QSQLITE driver.

| Check | Result |
| --- | --- |
| Matching-Qt native build via scripts/build-native.sh | Pass |
| Backend QtTest suite | 13 passes, zero failures (includes setup/teardown) |
| QML workflow suite | 10 passes, zero failures (includes setup/teardown) |
| Actual Basecamp module discovery/load | Pass: Successfully loaded UI module: logos_forum |
| Native state through Basecamp QtRO bridge | Pass: FORUM_STATE_READY 1 identities |
| Official lgx verify | Valid structure and hashes; unsigned |
| Standalone thread list and conversation screenshots | Rendered and inspected at desktop and 560px width |
| Install/package Python syntax and build shell syntax | Pass |
| Live cross-machine Delivery / live Store peer | Not exercised |
| Hosted GitHub CI / catalog publication | Not run; no remote configured |

The UI send tests use an injected fake bridge and verify exact post IDs for success/failure, including acknowledgements arriving before the send call returns. Backend exchange tests use two isolated databases with real signing and validation. These are local correctness checks, not a substitute for the network acceptance test in ROADMAP.md.

Artifacts: forum-desktop.png, forum-thread.png, forum-narrow.png, logos_forum-0.2.0-linux-amd64.lgx and SHA256SUMS. Screenshot examples are temporary synthetic data. The installed user database remains separate.
