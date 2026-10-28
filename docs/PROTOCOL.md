# Native integration and protocols v1/v2

## Host contract

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

The optional **Connect when Agora opens** preference defaults to false. Once
enabled, launch reuses an existing connected Delivery node, starts an existing
disconnected node, or creates one only when Delivery reports that its context
has not been initialized. It does not replace another app's node configuration.
Going offline cancels pending connection callbacks for the current session.

The adapter uses `getConnectionStatus`, `subscribe(contentTopic)`, `send(contentTopic,QByteArray)` and `storeQuery(queryJSON,peer,timeoutMs)`. Starting a node is a deliberate UI action using Core mode, logos.test preset, required anonymity routing and backfill. Connecting to a shared node does not reconfigure or stop it. Local disconnect stops forum sends/ingestion, not the shared node. Connected and PartiallyConnected transport states retain the subscription; partial connectivity may still require delivery retries and is not proof of receipt.

## Wire envelope

Content topic: `/logos-forum/1/commons/json`.

```json
{"id":"SHA256_HEX","payload":{"v":1,"nonce":"UUID","thread":"ROOT_ID_OR_EMPTY","board":"general","title":"Thread title","body":"Plain text","mode":"alias","author":"Display alias","pub":"BASE64_ED25519_PUBLIC_KEY","created":1234567890000},"signature":"BASE64_ED25519_SIGNATURE"}
```

The payload is serialized with Qt QJsonDocument Compact (sorted object keys, UTF-8); SHA-256 of those exact canonical bytes is the envelope ID. Ed25519 signs those same bytes. This v1 canonicalization is specified by the Qt implementation, not RFC 8785: other-language clients must reproduce its serialization and test interoperability before publishing. UTF-16 character bounds are 160 title / 12,000 body; wire maximum 64 KiB. Timestamp is Unix milliseconds, with at most five minutes of future skew. Boards are general/privacy/building/circles/governance. Thread roots have empty `thread`; replies point to a root hash. Orphan replies are retained for out-of-order recovery.

UID authors use the public key's SHA-256 fingerprint. Alias authors have arbitrary nonempty display text; matching text does not establish identity. Anonymous mode requires empty author, public key and signature. The stable message ID supports retry deduplication even in anonymous mode.

## Durable outbox

A successful compose transaction inserts the complete signed envelope and deletes its draft. Status starts queued. The pump attempts one item per five-second tick, with only one in flight. A matching messageSent request ID marks sent; errors or a 60-second missing acknowledgement mark failed. Early acknowledgements are buffered until the send result supplies the request ID. Retry retains the exact envelope/ID. Backoff grows exponentially to one hour; a user can explicitly retry failures. On restart, sending entries become queued. Incoming duplicate IDs do not add another post.

A transport acknowledgement is not an application-level receipt from all subscribers. Live intake is bounded before signature work: a 240-message burst budget refills at four messages per second using monotonic time. Payloads over 64 KiB are rejected before UTF-8 conversion. The QML bridge permits at most 32 outstanding receive requests, coalesces network-triggered snapshots over 100 ms, and permits only one snapshot request in flight. Deferred live messages are not marked received; the user is directed to recover them through bounded Store pages. Recovery pages do not consume the live budget, so a burst does not strand the saved history cursor. These controls limit local processing, not network traffic or Sybil identities. The UI requests database pages: 30 thread roots plus one latest-reply preview each, or one root plus 50 replies. Counts and search cover the full stored archive. Cursors include the filter context and deterministic timestamp/ID tie breakers. Changing filters resets paging. With activity sorting, new replies can move threads between pages; refreshing from the first page includes those changes. The diagnostic snapshot without a view is bounded to 200 recent records. Full database retention is independent; sustained resource measurements and stronger moderation remain acceptance work.

## Store recovery

Requests include one content topic, includeData, forward pagination, limit 50 and the cursor for that peer. Only statusCode 200 pages are ingested. Every message undergoes the same size/hash/signature/topic validation as live traffic; invalid entries are counted and rejected. Peer/cursor are persisted after a successful page. The UI lets the user request the next bounded page rather than flooding the network.

## Backend operations

`dispatch` accepts `snapshot`, `postInfo`, `replyPage`, `post`, `receive`, `identity`, `avatar`, `settings`, `draft`, `bookmark`, `next`, `delivery`, `retry`, `wire`, `historyPage`. All results contain `ok`; failures contain `error`. Private keys never appear in snapshots or wire output. SQLite is the local authority for drafts and pending sends; network transport is replaceable without changing the stored envelopes.

## Pinned API reference

The adapter is checked against [Delivery module v0.3.2](https://github.com/logos-co/logos-delivery-module/blob/v0.3.2/src/delivery_module_plugin.h), commit `c25b7868099949c375e7affdeb1502b354fd92e3`. This release uses raw byte-vector message payloads. Older README examples describing string/base64 live payloads do not describe this pinned contract. Store JSON payloads remain base64.

Local avatars are stored per identity in SQLite settings as a resized PNG. The avatar operation accepts a local file URL or remove=true; validates type, size and dimensions; applies orientation; and redraws into a fresh image to discard source metadata. Snapshot exposes only a normalized 64×64 pixel array for canvas rendering within Basecamp’s QML sandbox. This profile image is device-local and is never added to signed posts.

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
Uploads POST `/data`; downloads GET `/data/{cid}/network/stream?advertise=false`.
The node, rather than Agora, performs peer discovery and content availability.

Downloads enforce signed byte count while streaming, then SHA-256 and sniffed MIME
before copying into attachment storage. Images are bounded to 24 megapixels. File
names never select filesystem paths. Redirects are refused; requests have a
30-second upload / 90-second download inactivity timeout and a 180-second total deadline. Failed downloads
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
