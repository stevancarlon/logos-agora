# FURPS self-assessment — native 0.2.0

| Area | Evidence | Remaining acceptance work |
| --- | --- | --- |
| Functionality | Native threads/replies/quotes, boards/search/bookmarks, signed alias/UID and anonymous posts, identity rotation, Delivery adapter, paged Store ingestion | Live cross-machine Delivery and Store validation; authentic community discussions |
| Usability | Compact native QML UI, persistent composers, plain text selection, keyboard-accessible controls, narrow layout tests | User usability feedback and assistive technology validation |
| Reliability | SQLite WAL/transactions, crash recovery, durable outbox, signature rejection, deduplication, early-ack and failure tests | Long-running loss/reconnect tests against real peers; backup/restore UI |
| Performance | Single in-flight send, five-second pacing, exponential retry, 50-message history pages, 64 KiB envelopes | Large-history UI pagination, incoming abuse controls, sustained resource measurements |
| Supportability | C++17/QML source, build/install scripts, CI definition, verified local unsigned LGX, dual license, actual Basecamp load | Hosted green CI, signed catalog release, Windows/macOS builds, narrated demo |

Local verification: Basecamp 0.3.2 on Linux x86_64 loads the native module and its SQLite state through Qt Remote Objects. Tests execute on Qt 6.9.2 and system Qt 6.11.2. Separate test databases exchange genuine signed envelopes in-process; this is not proof of real network delivery. Synthetic screenshot discussions are visibly labeled and isolated in a temporary database.

This is a native integration build, not a claim that every LP-0026 acceptance criterion has been met. No real community adoption, public catalog submission, hosted CI result or live Store recovery is fabricated.

Attachment/video verification: 17 backend tests and 18 QML tests cover attachment transactions, restart persistence/export, local-only delivery, delayed callbacks after card destruction, video frames, pause, seek, volume/mute, stale controls, and stopping playback on navigation. Basecamp itself rendered 32 video frames with an advancing position during the native smoke test, with no sandbox changes or blocked URL accesses in this path. The separate Qt 6.9.2 runtime includes a pixel-only renderer; decoding/audio remain in the backend. Inline playback is currently capped at 640 pixels and 25 frame polls/second. Live network media transfer remains unimplemented.
