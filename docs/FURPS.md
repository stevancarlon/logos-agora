# FURPS self-assessment — native 0.3.1 candidate

| Area | Evidence | Remaining acceptance work |
| --- | --- | --- |
| Functionality | Native threads/replies/quotes, boards/search/bookmarks, signed alias/UID and anonymous posts, identity rotation, Delivery adapter, paged Store ingestion, signed v2 attachment references and Logos Storage transfer | Live cross-machine Delivery and Store validation; authentic community discussions |
| Usability | Compact native QML UI, persistent composers, plain text selection, keyboard-accessible controls, narrow layout tests | User usability feedback and assistive technology validation |
| Reliability | SQLite WAL/transactions, crash recovery, durable outbox, signature rejection, deduplication, early-ack and failure tests | Long-running loss/reconnect tests against real peers; backup/restore UI |
| Performance | Single in-flight send, five-second pacing, exponential retry, 50-message history pages, 64 KiB envelopes, live intake budget, coalesced snapshots and database-backed feed/reply pages | Sustained resource measurements, stronger moderation |
| Supportability | C++17/QML source, build/install scripts, green default-branch CI, published unsigned Linux alpha/catalog, dual license, verified Linux/Windows/Apple Silicon Basecamp loading and media | Intel Mac host integration, published desktop kits, full narrated demo |

Current evidence (26 October 2026): [default-branch Linux checks](https://github.com/stevancarlon/logos-agora/actions/runs/40337478339) and [desktop checks](https://github.com/stevancarlon/logos-agora/actions/runs/40337478401) pass 23 backend and 24 QML tests per target. Windows and Apple Silicon archives additionally pass actual Basecamp MP4/WebM playback; see [platform evidence and limits](PLATFORMS.md). Intel host integration, cross-machine exchange and authentic adoption remain open. The published release remains the unsigned Linux alpha, not the newer development archives. Its community-catalog GUI installation and actual UI/backend load also passed in a disposable Ubuntu/Xvfb desktop with the companion runtime; see [installation scope](../INSTALL.md).

The dated results below are a verification history; earlier test counts and pending states are superseded by this current summary. Publisher signing, backup/restore UI, assistive-technology testing and sustained benchmarks are additional quality work, not claimed as explicit prize requirements. The required narrated end-to-end demo and authentic conversations are still incomplete.

Local verification: Basecamp 0.3.2 on Linux x86_64 loads the native module and its SQLite state through Qt Remote Objects. Tests execute on Qt 6.9.2 and system Qt 6.11.2. Three independent Basecamp processes now exchange signed envelopes over an isolated loopback relay and recover them through a real Store query; this is not cross-machine or public mix-routing evidence. Synthetic screenshot discussions are visibly labeled and isolated in a temporary database.

This is a native integration build, not a claim that every LP-0026 acceptance criterion has been met. No real community adoption, public catalog submission, hosted CI result or live Store recovery is fabricated.

Attachment/video verification: 17 backend tests and 18 QML tests cover attachment transactions, restart persistence/export, local-only delivery, delayed callbacks after card destruction, video frames, pause, seek, volume/mute, stale controls, and stopping playback on navigation. Basecamp itself rendered 32 video frames with an advancing position during the native smoke test, with no sandbox changes or blocked URL accesses in this path. The separate Qt 6.9.2 runtime includes a pixel-only renderer; decoding/audio remain in the backend. Inline playback is currently capped at 640 pixels and 25 frame polls/second. Superseded by the v0.3 media acceptance results below.

2026-10-11 acceptance update: 17 backend and 20 QML checks pass. The private Basecamp relay test verifies queued-post persistence across shutdown/restart, thread/reply receipt, Store recovery without subscription, and identical nonduplicated message IDs in three separate databases. Evidence: `artifacts/network-restart/result.json`. A checksummed precompiled release kit and isolated installer check are available; catalog publication, hosted CI and clean-OS installation remain unverified.

2026-10-11 media acceptance: 18 backend and 21 QML tests pass. Two actual Logos
Storage v0.5.3 nodes exchange PNG, MP4 and PDF with exact byte/hash verification.
The actual Basecamp bridge uploads an MP4 before offline queuing, delivers its v2
reference after restart, fetches and validates the bytes on the recipient, and
recovers the reference through Store on a third profile. Evidence:
`artifacts/storage-release-candidate/result.json`. Nodes are isolated on one host;
public-network retention, cross-machine connectivity and automatic Storage setup
remain unverified or unfinished. Local originals and older local conversations
are never silently published.

Live-intake hardening: 19 backend and 22 QML checks pass. Tests exhaust the live
budget with invalid traffic, recover a valid message through Store despite that
budget, verify cursor persistence and deduplication after refill, and coalesce a
100-request UI refresh burst into one snapshot. These are local processing limits,
not Sybil resistance or proof of acceptable performance with a large archive.

Pagination verification: 21 backend and 24 QML checks pass on Qt 6.9.2. A temporary 12,000-root archive returns bounded pages and finds its oldest record; feed, search and diagnostic snapshot took 25 ms together on this host. A 115-reply test covers page traversal without duplicates, complete counts, unloaded-reply search and locating newly submitted replies. UI checks exercise next/previous navigation, filter resets, and scrolling to a submitted reply beyond the first page. The updated build also passes private Basecamp relay/restart/Store recovery and isolated release installation (`artifacts/network-pagination-check/result.json`, `artifacts/release-pagination-check/result.json`). This is not a sustained memory or network benchmark. Evidence: `artifacts/pagination-verification.json`.

Fresh Ubuntu 24.04 userspace: the precompiled 0.3.0 kit installs and loads its actual Basecamp UI/backend in an unprivileged, offline container. Corrupted files are rejected. The archive hash and scope are recorded in `artifacts/ubuntu-release-check/result.json`. This shares the host kernel and uses offscreen rendering; full desktop and clean-OS acceptance remain open.

Published 0.3 alpha: [default-branch CI](https://github.com/stevancarlon/logos-agora/actions/runs/38190510549) passes all 45 tests, official LGX validation and release packaging at commit `d62aaa29a064baa56e5a537fbe1a013d81df3788`. The exact CI kit passes the Ubuntu userspace check; see `artifacts/ci-ubuntu-release-check/result.json`. [Release assets](https://github.com/stevancarlon/logos-agora/releases/tag/v0.3.0-alpha.1) include the prebuilt kit, unsigned LGX, hashes and community catalog metadata. The public index and package bytes were fetched and their size/hash verified. Installation through Basecamp's catalog UI, publisher signatures, full desktop/cross-machine acceptance, narrated demo and authentic adoption remain unverified.

Desktop portability: 22 backend and 24 QML tests pass on Linux x86_64, Windows x86_64 (MinGW), Intel macOS and Apple Silicon macOS. Official LGX structure validation passes for all four native variants. This does not establish Basecamp load compatibility or complete end-user installation. The official Apple Silicon Basecamp bundle has matching Qt 6.9.2 framework identities; runtime dependency staging and actual host checks are in progress. See [PLATFORMS.md](PLATFORMS.md) for evidence and remaining work.
