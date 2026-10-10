# Local verification — 2026-10-08

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
