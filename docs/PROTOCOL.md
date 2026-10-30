# Native integration and protocols v1/v2

## Host contract

The source module descriptor is [`native/forum/module.json`](../native/forum/module.json). Packaging and installation read this descriptor and emit Basecamp’s required `manifest.json`; release kits include both names with matching target-specific fields. Logos Delivery is the transport layer of [Logos Messaging](https://github.com/logos-messaging), previously known as Waku. Agora integrates through the Delivery module API below.

`logos_forum` is a `ui_qml` module. Basecamp loads `qml/Main.qml` and runs `forum_backend.so` in its UI host, exposed through Qt Remote Objects. QML gets `logos.module("logos_forum")`; `dispatch(JSON)` returns a JSON string through `logos.watch(...)`. Backend `changed` signals trigger a fresh snapshot. `receiveBytes(QByteArray)` avoids ambiguous byte/string coercion. The native `outboundPayload` QByteArray property supplies the delivery payload.

Dependencies: `delivery_module >=0.3.0`. Tested host: Basecamp 0.3.2, Qt 6.9.2, Linux x86_64. Calls use `logos.callModuleAsync` with a 15-second timeout. The response wrapper `{success,value,error}` is checked before using the value. Events arrive through `moduleEventReceived(moduleName,eventName,data)` after registering `onModuleEvent`.

Public testnet setup also depends on a usable RLN membership. A successful
subscription alone does not establish that publishing works. On 2026-10-26,
the local installation was upgraded to Delivery 0.4.0, RLN 0.12.0 and LEZ RLN
5.1.0 for the current `https://testnet.lez.logos.co/` deployment; the older
RLN provider still pointed at the retired testnet sequencer. New membership
provisioning waits for a funded local payer. Registration price and fee reserve
come from the network and can change. Until a matching `messageSent` arrives,
posts must remain pending or failed, even when the node has connected peers.

The backend `autoConnect` preference defaults to true; existing explicit false
values and the dedicated examples profile remain local-only. The app has no
separate Network settings screen. On launch it reuses an existing connected Delivery node, starts an existing
disconnected node, or creates one only when Delivery reports that its context
has not been initialized. It does not replace another app's node configuration.
Going offline cancels pending connection callbacks for the current session.

The adapter uses `getConnectionStatus`, `subscribe(contentTopic)`, `send(contentTopic,QByteArray)` and `storeQuery(queryJSON,peer,timeoutMs)`. Automatic startup uses Core mode, logos.test preset, required anonymity routing and backfill when no existing node is available. Connecting to a shared node does not reconfigure or stop it. Local disconnect stops forum sends/ingestion, not the shared node. Connected and PartiallyConnected transport states retain the subscription; partial connectivity may still require delivery retries and is not proof of receipt.

## Wire envelope

Content topic: `/logos-forum/1/commons/json`.

```json
{"id":"SHA256_HEX","payload":{"v":1,"nonce":"UUID","thread":"ROOT_ID_OR_EMPTY","board":"general","title":"Thread title","body":"Plain text","mode":"alias","author":"Display alias","pub":"BASE64_ED25519_PUBLIC_KEY","created":1234567890000},"signature":"BASE64_ED25519_SIGNATURE"}
```

The payload is serialized with Qt QJsonDocument Compact (sorted object keys, UTF-8); SHA-256 of those exact canonical bytes is the envelope ID. Ed25519 signs those same bytes. This v1 canonicalization is specified by the Qt implementation, not RFC 8785: other-language clients must reproduce its serialization and test interoperability before publishing. UTF-16 character bounds are 160 title / 12,000 body; wire maximum 64 KiB. Timestamp is Unix milliseconds, with at most five minutes of future skew. Boards are general/privacy/building/circles/governance. Thread roots have empty `thread`; replies point to a root hash. Orphan replies are retained for out-of-order recovery.

UID authors use the public key's SHA-256 fingerprint. Alias authors have arbitrary nonempty display text; matching text does not establish identity. Anonymous mode requires empty author, public key and signature. The stable message ID supports retry deduplication even in anonymous mode.

## Durable outbox

A successful compose transaction inserts the complete signed envelope and deletes its draft. Status starts queued. The pump attempts one item per five-second tick, with only one in flight. A matching messageSent request ID marks sent; errors or a 90-second missing acknowledgement mark failed. The watchdog allows Delivery's own retry window (observed at roughly 65 seconds) to return its terminal event before Agora times out. Early acknowledgements are buffered until the send result supplies the request ID. Retry retains the exact envelope/ID. Backoff grows exponentially to one hour; a user can explicitly retry failures. Each failed message exposes Retry sending; `retry` with an `id` clears backoff only for that failed envelope. Sent or in-flight posts are never requeued by this action. Offline retries wait for connection; online retries recheck credentials before sending. On restart, sending entries become queued. Incoming duplicate IDs do not add another post.

Before claiming an outbox entry, Agora reads Delivery's `rlnState` and uses
its resolved `registryId` / `rlnIdentifier` to call the RLN module's
`get_membership_state` (90-second timeout). Only `active` or `grace_period`
allows publishing; an explicitly RLN-disabled node needs no membership.
Readiness is refreshed after 60 seconds and blocked checks retry after 30
seconds without claiming posts or incrementing delivery attempts. Unknown,
malformed, unsupported, timed-out, or ambiguous responses pause publishing;
subscription and local composition remain available. Disconnect invalidates
outstanding callbacks, and a 110-second watchdog releases a missing callback.
A matching acknowledgement remains the only sent transition. The badge tooltip
explains the pause. Hosts lacking this readiness API require
an updated Delivery module; the adapter does not silently skip the check.

A transport acknowledgement is not an application-level receipt from all subscribers. Live intake is bounded before signature work: a 240-message burst budget refills at four messages per second using monotonic time. Payloads over 64 KiB are rejected before UTF-8 conversion. The QML bridge permits at most 32 outstanding receive requests, coalesces network-triggered snapshots over 100 ms, and permits only one snapshot request in flight. Deferred live messages are not marked received; the user is directed to recover them through bounded Store pages. Recovery pages do not consume the live budget, so a burst does not strand the saved history cursor. These controls limit local processing, not network traffic or Sybil identities. The UI requests database pages: 30 thread roots plus one latest-reply preview each, or one root plus 50 replies. Counts and search cover the full stored archive. Cursors include the filter context and deterministic timestamp/ID tie breakers. Changing filters resets paging. With activity sorting, new replies can move threads between pages; refreshing from the first page includes those changes. The diagnostic snapshot without a view is bounded to 200 recent records. Full database retention is independent; sustained resource measurements and stronger moderation remain acceptance work.

## Store recovery

Requests include one content topic, includeData, forward pagination, limit 50 and the cursor for that peer. Only statusCode 200 pages are ingested. Every message undergoes the same size/hash/signature/topic validation as live traffic; invalid entries are counted and rejected. Peer/cursor are persisted after a successful page. The UI lets the user request the next bounded page rather than flooding the network.

## Backend operations

`dispatch` accepts `snapshot`, `postInfo`, `postReference`, `replyPage`, `post`, `receive`, `identity`, `avatar`, `settings`, `draft`, `bookmark`, `next`, `delivery`, `retry`, `wire`, `historyPage`. All results contain `ok`; failures contain `error`. Private keys never appear in snapshots or wire output. SQLite is the local authority for drafts and pending sends; network transport is replaceable without changing the stored envelopes.

`postReference` resolves an 8–64 digit hexadecimal prefix across the local archive. It returns `found` with the post and `threadAvailable`, or `missing` / `ambiguous`; ambiguous prefixes never select an arbitrary post. Quote previews use this local lookup without fetching remote attachments. Navigation uses `replyPage` when the referenced reply is outside the loaded page. Quote formatting and links do not modify signed post bodies.

## Pinned API reference

The adapter is checked against [Delivery module v0.3.2](https://github.com/logos-co/logos-delivery-module/blob/v0.3.2/src/delivery_module_plugin.h), commit `c25b7868099949c375e7affdeb1502b354fd92e3`. This release uses raw byte-vector message payloads. Older README examples describing string/base64 live payloads do not describe this pinned contract. Store JSON payloads remain base64.

Local avatars are stored per identity in SQLite settings as a resized PNG. The avatar operation accepts a local file URL or remove=true; validates type, size and dimensions; applies orientation; and redraws into a fresh image to discard source metadata. Snapshot exposes only normalized 64×64 pixel arrays for canvas rendering within Basecamp’s QML sandbox: `avatar` for the active profile and `avatars` keyed by signing identity for visible authors. Each portrait is included once per snapshot, independently of how many posts use it. Posts retain their author's portrait when the active identity changes; matching display names alone never select an avatar, and anonymous posts use no identity photo. This profile image is device-local and is never added to signed posts.

## Local attachment operations

`attachmentImport`, `attachmentPreview`, `attachmentOpen`, and `attachmentExport` manage device-local files. `post.attachments` accepts up to four staged attachment IDs. Association is transactional; missing, duplicate or already-used IDs reject the post. Snapshot posts include only attachment ID, name, MIME and byte count. Thumbnails are requested separately. Without an uploaded CID, attached posts and replies under local-only roots use status `local`; next/delivery/wire exclude them. With uploaded CIDs for every attachment, new posts use protocol v2 and enter the normal Delivery queue. Existing local-only posts never change IDs or become published automatically.

### Device-local video session

`attachmentVideo` accepts `action` (play/pause/seek/volume/mute/state/stop), an attachment `id`, and the last received frame `generation`. Play resolves only stored video IDs and checks canonical containment within private attachment storage. Controls from a stale attachment ID cannot affect the active video. State returns time, duration, playing/seekable, volume/mute, errors and generation; a changed generation includes a bounded RGBA frame packet. No media file URL or signing material is sent to the renderer. Frames travel over the existing backend bridge, not Delivery. Decoder output is reduced to a maximum 640 x 640 pixels.

## Shared attachments (v2)

The content topic stays `/logos-forum/1/commons/json`. A v2 payload adds a signed
`attachments` array (one to four entries). Each entry contains `name`, `mime`,
`bytes`, `cid`, and lowercase SHA-256 `sha256`. All fields participate in the
canonical hash and signature. V1 remains text-only; older clients reject v2.
Supported types are PNG, JPEG, MP4, WebM and PDF, at most 64 MiB per file. Received
metadata and post insertion are transactional, with attachment IDs derived from
post ID and array index. Duplicate envelopes do not duplicate metadata.

`attachmentUpload` stages an unattached local file in Logos Storage;
`attachmentFetch` explicitly retrieves a remote reference. `attachmentTransfer`
returns running/complete/failed, byte progress and error; `attachmentCancel` aborts.
One transfer runs at a time. The endpoint is a user-configured literal loopback
HTTP URL ending `/api/storage/v1`, with an explicit port and no credentials,
query or fragment. No remote gateway or central application server is used.
Uploads POST `/data` with the validated MIME type, then POST
`/data/{cid}/advertise?advertise=true` to refresh the provider announcement even
when Storage deduplicates an existing file. Failure of either request leaves the
original staged file available for retry and does not persist a publishable CID.
Announcement acceptance is not proof of remote retrieval. Downloads GET
`/data/{cid}/network/stream?advertise=false`.
The node, rather than Agora, performs peer discovery and content availability.

Downloads enforce signed byte count while streaming, then SHA-256 and sniffed MIME
before copying into attachment storage. Images are bounded to 24 megapixels. File
names never select filesystem paths. Redirects are refused; requests have a
30-second upload/announcement and 150-second download inactivity timeout, with
an independent 180-second total deadline covering all phases. Failed downloads
are deleted; failed uploads retain the staged original. Original upload metadata
is preserved. Content retention depends on Storage providers remaining available;
upload success is not a permanent-availability promise or anonymity guarantee.

## Delivery 0.4.0 compatibility check

On 26 October 2026 the current development build also passed the private
Basecamp relay test against the official catalog Delivery 0.4.0 package. Signed
alias and anonymous envelopes each passed thread/reply receipt, offline-post
restart, Store recovery and independent-database deduplication checks. The
0.4.0 LGX was obtained through Basecamp's catalog installer; this check does not
claim that the source tag or the published Agora alpha was tested. Public
mix routing and cross-machine connectivity remain unverified. The pinned 0.3.2
contract above remains the reproducible source reference.

## Public Delivery receipt — 28 October 2026

After funding and registering a membership, the welcome thread received a matching
`messageSent` event and arrived in an independent Basecamp profile through the
public `logos.test` network. Envelope hashes match. Both processes ran on one
Linux host; cross-machine receipt and network anonymity remain unverified. See
[the receipt record](evidence/public-delivery-20261028.json) and
[current setup](NETWORK.md).
