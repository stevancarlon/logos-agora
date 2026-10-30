# Agora release acceptance

Use disposable profiles for synthetic acceptance messages. Never seed the real
user database or cite these tests as organic adoption.

## Automated host integration

After the matching-Qt native build and companion runtime installation:

```sh
python3 scripts/check-basecamp-network.py --basecamp "$HOME/Applications/LogosBasecamp-Agora" --modules "$HOME/.local/share/Logos/LogosBasecamp/modules"
python3 scripts/check-basecamp-peers.py --basecamp "$HOME/Applications/LogosBasecamp-Agora" --modules "$HOME/.local/share/Logos/LogosBasecamp/modules"
```

Add `--anonymous` to the peer check to verify anonymous-display envelopes and absence of author/public-key/signature fields in all three databases. This does not test network anonymity.

The first check starts the production `logos.test` preset and subscribes without
creating or publishing posts. The second starts a private loopback relay network
(cluster 42, static peers, discovery disabled). It creates an offline queued post,
closes the producer, reopens its database in a new Basecamp process, exchanges a
signed thread/reply, and starts an unsubscribed third process to retrieve history
through an actual Store query. It verifies the same two message IDs in all three
independent forum databases. Each node has its own working directory and Store
database. JSON results and logs are saved under artifacts/.

This proves host bridge, byte transport, database persistence and private relay
integration on one machine. It does not prove cross-machine connectivity, public
mix routing, network anonymity, authentic adoption or catalog installation.

## Precompiled installation

```sh
python3 scripts/build-release.py --lgx /absolute/path/to/lgx
python3 scripts/check-release.py --archive artifacts/agora-0.3.0-linux-amd64.tar.gz --qt "$HOME/Qt/6.9.2/gcc_64" --basecamp "$HOME/Applications/LogosBasecamp-0.3.2-x86_64.AppImage" --modules "$HOME/.local/share/Logos/LogosBasecamp/modules"
```

The check rejects a deliberately corrupted file, installs the extracted kit into
temporary paths, clears inherited Qt runtime overrides, and loads the actual
forum GUI/backend using the original AppImage and generated launcher. No app code
is compiled during installation. This is isolated-profile evidence, not a fresh OS
test. Follow RELEASE.md on a separate clean Linux installation before submission.

## Cross-machine and public-network gates

On two separate computers (for example Linux and Intel macOS), install the
verified candidate kit for each platform and Delivery 0.3.2. Do not start the
Intel test until its Basecamp host integration has passed. Record kit hashes, Basecamp/Delivery versions, OS and timestamp. Use separate
identities and an agreed test thread. Start/connect Delivery on both machines.
Verify each machine receives the other's signed replies; verify anonymous display
and identity rotation independently. Record matching message IDs at both ends;
the sender's sent indicator alone is insufficient.

Take B offline, send another post from A, restart B and query an available Store
peer. Verify the missed post and existing replies are present once each. Repeat
after restarting B again to check the persisted cursor. Queue a post while A is
offline, restart A, reconnect, and check it arrives once at B. Record failures and
latency; do not mark these gates passed from a local relay result.

## Comparing receipt evidence

Use `scripts/check-peer-receipts.py` on each test computer after each phase.
Supply the complete 64-character message IDs for the agreed test thread and
replies. Use a separate output file for live exchange, offline recovery and
restart checks. The database is opened read-only, including committed WAL data;
message bodies, aliases, identity keys and local paths are not exported.

```sh
python3 scripts/check-peer-receipts.py snapshot --database /absolute/path/to/forum.sqlite --installation linux-a --phase live --id FULL_THREAD_ID --id FULL_REPLY_ID --output linux-live.json
```

On the other computer, use its database path and `--installation intel-mac-b`,
with the same IDs and phase. Copy only these receipt JSON files to one computer:

```sh
python3 scripts/check-peer-receipts.py compare linux-live.json mac-live.json
```

Comparison fails for missing messages, differing envelope hashes/parents, or
messages that neither installation records as received. It never treats two
sent indicators as incoming receipt. A matching report establishes database
agreement only: retain the actual two-computer recording, kit hashes, transport
logs and offline/restart sequence to establish how those records arrived.
Installation labels are user-supplied and cannot prove independent hardware.
The output deliberately leaves `crossMachineVerified` false. Do not copy the
SQLite database between machines: that would copy identities and invalidate the
independent receipt test. Hashes and timestamps still correlate selected test
messages, so use agreed test conversations for shared evidence.

## Submission gates still requiring evidence

- Clean OS installation using published artifacts, including media runtime.
- Prebuilt release in a Logos module catalog and appropriate package signing.
- Green hosted CI on the repository's default branch.
- Authentic discussions by real participants; obtain consent for any identifiable
  material shown in the demo. Do not invent testimonials or usage counts.
- Narrated recording of installation, identity choices, thread/reply/quote,
  offline retry, peer receipt and missed-message recovery. Show media transfer through local Storage nodes and disclose the manual setup requirement.
- Update README, FURPS and submission template with links to actual evidence.

## Demo recording outline

1. Introduce Agora and its local-first C++/QML/SQLite architecture.
2. Install the candidate on a clean profile; explain the companion runtime.
3. Choose an identity, create a thread, and reply from a second machine.
4. Quote a reply, search, rotate identity and show anonymous display.
5. Disconnect, compose, restart and reconnect; demonstrate durable delivery.
6. Recover missed messages from Store and compare IDs on both machines.
7. Demonstrate attachments honestly, including which data remains device-local.
8. Show CI, catalog installation, adoption evidence and remaining limitations.

This outline is preparation, not a recorded demo or submission.

## Fresh Ubuntu userspace

```sh
python3 scripts/check-linux-container.py --archive artifacts/agora-0.3.0-linux-amd64.tar.gz --qt "$HOME/Qt/6.9.2/gcc_64" --basecamp "$HOME/Applications/LogosBasecamp-0.3.2-x86_64.AppImage" --modules "$HOME/.local/share/Logos/LogosBasecamp/modules"
```

This builds a pinned Ubuntu 24.04 container with explicit desktop libraries, then
installs and loads the precompiled kit as an unprivileged user with runtime
network access disabled. Inputs are read-only; only the result directory is
writable on the host. Use `--build-network host` if Docker's default network cannot
download apt packages; this affects image preparation only. Evidence records the
archive hash. This passed for the 0.3.0 candidate, including checksum-corruption
rejection and actual Basecamp UI/backend initialization. It shares the host kernel
and uses offscreen rendering, so it does not establish full desktop, audio-device,
fresh Qt download, clean-OS or cross-machine acceptance.
