# Native integration and protocol v1

## Host contract

`logos_forum` is a `ui_qml` module. Basecamp loads `qml/Main.qml` and runs `forum_backend.so` in its UI host, exposed through Qt Remote Objects. QML gets `logos.module("logos_forum")`; `dispatch(JSON)` returns a JSON string through `logos.watch(...)`. Backend `changed` signals trigger a fresh snapshot. `receiveBytes(QByteArray)` avoids ambiguous byte/string coercion. The native `outboundPayload` QByteArray property supplies the delivery payload.

Dependencies: `delivery_module >=0.3.0`. Tested host: Basecamp 0.3.2, Qt 6.9.2, Linux x86_64. Calls use `logos.callModuleAsync` with a 15-second timeout. The response wrapper `{success,value,error}` is checked before using the value. Events arrive through `moduleEventReceived(moduleName,eventName,data)` after registering `onModuleEvent`.

The adapter uses `getConnectionStatus`, `subscribe(contentTopic)`, `send(contentTopic,QByteArray)` and `storeQuery(queryJSON,peer,timeoutMs)`. Starting a node is a deliberate UI action using Core mode, logos.test preset, required anonymity routing and backfill. Connecting to a shared node does not reconfigure or stop it. Local disconnect stops forum sends/ingestion, not the shared node.

## Wire envelope

Content topic: `/logos-forum/1/commons/json`.

```json
{"id":"SHA256_HEX","payload":{"v":1,"nonce":"UUID","thread":"ROOT_ID_OR_EMPTY","board":"general","title":"Thread title","body":"Plain text","mode":"alias","author":"Display alias","pub":"BASE64_ED25519_PUBLIC_KEY","created":1234567890000},"signature":"BASE64_ED25519_SIGNATURE"}
```

The payload is serialized with Qt QJsonDocument Compact (sorted object keys, UTF-8); SHA-256 of those exact canonical bytes is the envelope ID. Ed25519 signs those same bytes. This v1 canonicalization is specified by the Qt implementation, not RFC 8785: other-language clients must reproduce its serialization and test interoperability before publishing. UTF-16 character bounds are 160 title / 12,000 body; wire maximum 64 KiB. Timestamp is Unix milliseconds, with at most five minutes of future skew. Boards are general/privacy/building/circles/governance. Thread roots have empty `thread`; replies point to a root hash. Orphan replies are retained for out-of-order recovery.

UID authors use the public key's SHA-256 fingerprint. Alias authors have arbitrary nonempty display text; matching text does not establish identity. Anonymous mode requires empty author, public key and signature. The stable message ID supports retry deduplication even in anonymous mode.

## Durable outbox

A successful compose transaction inserts the complete signed envelope and deletes its draft. Status starts queued. The pump attempts one item per five-second tick, with only one in flight. A matching messageSent request ID marks sent; errors or a 60-second missing acknowledgement mark failed. Early acknowledgements are buffered until the send result supplies the request ID. Retry retains the exact envelope/ID. Backoff grows exponentially to one hour; a user can explicitly retry failures. On restart, sending entries become queued. Incoming duplicate IDs do not add another post.

A transport acknowledgement is not an application-level receipt from all subscribers. No flood control or Sybil resistance is claimed for hostile incoming peers. The current snapshot displays up to 10,000 stored posts; full database retention is independent. Large-history pagination/moderation needs additional work before public deployment.

## Store recovery

Requests include one content topic, includeData, forward pagination, limit 50 and the cursor for that peer. Only statusCode 200 pages are ingested. Every message undergoes the same size/hash/signature/topic validation as live traffic; invalid entries are counted and rejected. Peer/cursor are persisted after a successful page. The UI lets the user request the next bounded page rather than flooding the network.

## Backend operations

`dispatch` accepts `snapshot`, `post`, `receive`, `identity`, `avatar`, `settings`, `draft`, `bookmark`, `next`, `delivery`, `retry`, `wire`, `historyPage`. All results contain `ok`; failures contain `error`. Private keys never appear in snapshots or wire output. SQLite is the local authority for drafts and pending sends; network transport is replaceable without changing the stored envelopes.

## Pinned API reference

The adapter is checked against [Delivery module v0.3.2](https://github.com/logos-co/logos-delivery-module/blob/v0.3.2/src/delivery_module_plugin.h), commit `c25b7868099949c375e7affdeb1502b354fd92e3`. This release uses raw byte-vector message payloads. Older README examples describing string/base64 live payloads do not describe this pinned contract. Store JSON payloads remain base64.

Local avatars are stored per identity in SQLite settings as a resized PNG. The avatar operation accepts a local file URL or remove=true; validates type, size and dimensions; applies orientation; and redraws into a fresh image to discard source metadata. Snapshot exposes only a normalized 64×64 pixel array for canvas rendering within Basecamp’s QML sandbox. This profile image is device-local and is never added to signed posts.

## Local attachment operations

`attachmentImport`, `attachmentPreview`, `attachmentOpen`, and `attachmentExport` manage device-local files. `post.attachments` accepts up to four staged attachment IDs. Association is transactional; missing, duplicate or already-used IDs reject the post. Snapshot posts include only attachment ID, name, MIME and byte count. Thumbnails are requested separately. Attached posts and replies under local-only roots use status `local`; next/delivery/wire exclude them. The signed v1 network envelope has no attachment fields and no media transfer support.

### Device-local video session

`attachmentVideo` accepts `action` (play/pause/seek/volume/mute/state/stop), an attachment `id`, and the last received frame `generation`. Play resolves only stored video IDs and checks canonical containment within private attachment storage. Controls from a stale attachment ID cannot affect the active video. State returns time, duration, playing/seekable, volume/mute, errors and generation; a changed generation includes a bounded RGBA frame packet. No media file URL or signing material is sent to the renderer. Frames travel over the existing backend bridge, not Delivery. Decoder output is reduced to a maximum 640 x 640 pixels.
