# Release acceptance

Implemented: native Basecamp module, C++/SQLite backend, signed envelopes, anonymous mode, rotation, durable outbox, Delivery adapter, bounded Store recovery, discussion UI, native tests, install/build/package scripts.

Before a public network release:

1. Use two isolated Basecamp profiles on separate machines to verify subscription, signed/anonymous exchange, parent/reply order, offline retry and reconnect without duplicates.
2. Test Store recovery against an available peer, including multiple pages and a persisted cursor after restart.
3. Measure long-run storage and memory; database-backed feed/reply pagination is implemented. Live intake now has a burst budget and bounded/coalesced UI requests; stronger moderation and Sybil resistance remain separate work.
4. Push to an authorized repository, run hosted CI, publish a signed catalog package and record the narrated end-to-end demo.
5. Invite authentic community use and collect discussion evidence without fabricated accounts or examples.

The old browser prototype is retained for reference. Continued product work targets native/.
