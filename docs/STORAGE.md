# Sharing media through Logos Storage

Agora 0.3 supports images, video and PDFs through Logos Storage. Text and signed
attachment references travel through Delivery; file bytes travel through Storage.
There is no central forum server. Each participant uses a local Storage node.

## Connect a node

Use the official [Logos Storage implementation](https://github.com/logos-storage/logos-storage-nim).
Public relay retrieval uses v0.5.3 plus the pinned
[Agora public-download patches](../patches/README.md#storage-public-download-correction)
on Linux x86_64. The unpatched binary failed the public receipt checks. Apply all three patches,
including relay forwarding validation and renewal, on the publisher and reader.
With the tested `storage` executable installed,
run a node with a persistent directory and a loopback-only API:

```sh
storage --data-dir="$HOME/.local/share/AgoraStorage" --api-bindaddr=127.0.0.1 --api-port=8080
```

For the public `logos.test` network, generate a TOML configuration from the
[official fleet](https://fleets.logos.co/logos-test/storage-network.json). This
avoids relying only on bootstrap records bundled with an older binary:

```sh
python3 scripts/storage-network-config.py --output "$HOME/.config/agora/storage-public.toml"
storage --config-file="$HOME/.config/agora/storage-public.toml" --data-dir="$HOME/.local/share/AgoraStorage" --api-bindaddr=127.0.0.1 --api-port=8080
```

The generator refuses to overwrite an existing file. For updates, generate a
new filename, inspect it, and change the node's `--config-file` argument. Keep
the same data directory so its identity and attachment blocks survive. `--mix`
also includes the fleet's Mix pool and DHT proxies; enabling Mix alone without
these does not configure Mix discovery. Agora's current HTTP downloads use the
direct transport. Configuration generation does not establish public retrieval.

Keep this process running. Node discovery/bootstrap and network reachability must
be configured for the network your participants use. Public PNG/MP4/PDF retrieval now passes with fresh readers through public
discovery and relays on one host; an independent GitHub-hosted reader now verifies all three original fixture CIDs with matching sizes and hashes. See [the receipt](evidence/PUBLIC-STORAGE-20261030.md).
The separate private integration checks use loopback-connected nodes.

Set the forum profile’s `storageEndpoint` through the backend `settings`
operation during installation or integration setup:

```json
{"op":"settings","storageEndpoint":"http://127.0.0.1:8080/api/storage/v1"}
```

Existing configuration is retained; Agora no longer exposes a Network settings
screen. Remote HTTP gateways are not accepted. The endpoint is saved per profile.

For a persistent Linux desktop setup, the node can run as a systemd user service.
Keep `--api-bindaddr=127.0.0.1`, choose an unused API port, and keep its data
directory across upgrades. The local development installation uses
`agora-storage.service`, patched Storage v0.5.3, and port `18080`; its API is
`http://127.0.0.1:18080/api/storage/v1`. Check it with
`systemctl --user status agora-storage.service`. The service starts at user login.
This is a separate Storage process built from the pinned upstream source and
Agora patch because Agora's HTTP integration
does not consume the Basecamp Storage module's native upload/download methods.

On 2026-10-26 this setup connected to public testnet peers and served its local
API. That establishes node connectivity, not public attachment retrieval or
retention; the two-node transfer evidence below remains the media validation.

## Post and read

Attach a PNG/JPEG, MP4/WebM or PDF to a new thread or reply and publish it. Agora
uploads the files sequentially before queuing the signed post. The original file
bytes, including embedded metadata, become available through Storage. If an upload
fails, the composer and local file remain available to retry. Already uploaded
files can remain on Storage even if a later upload or post fails.

Each upload uses the file's validated MIME type and explicitly refreshes the
Storage provider announcement, including when the node already has those bytes.
An announcement failure keeps the original staged file available for retry.
The node accepting the announcement does not prove a remote download succeeded.

Readers see a **Fetch** button with the attachment size. Fetching is explicit;
incoming posts never automatically download media. After download, Agora verifies
the exact signed size, SHA-256 and MIME type. Images render inline, videos use the
embedded player, and PDFs open in the system viewer. Downloaded files remain in
the forum's private attachment directory across restarts.

Without a configured Storage node, attached posts remain local-only. Adding a node
later does not publish old local conversations. Do not configure Storage for the
synthetic examples profile. Storage node retention and uptime determine continued
availability; an upload is not a permanence or anonymity guarantee.

## Reproduce the integration test

```sh
QMAKE="$HOME/Qt/6.9.2/gcc_64/bin/qmake" scripts/build-native.sh
python3 scripts/check-storage.py --storage /absolute/path/to/storage --basecamp "$HOME/Applications/LogosBasecamp-Agora" --modules "$HOME/.local/share/Logos/LogosBasecamp/modules"
```

This starts isolated provider and consumer Storage nodes, exercises an MP4 through
the actual Basecamp bridge plus private Delivery peers, and checks PNG/MP4/PDF
upload, signed-reference ingestion, fetch and exact export bytes through the native
backend. The Basecamp portion also verifies restart delivery and Store recovery.
It does not establish cross-machine connectivity or public-network retention.

To test public retrieval from a fresh reader with current fleet records:

```sh
python3 scripts/check-storage-receipt.py --storage /absolute/path/to/storage --config-file "$HOME/.config/agora/storage-public.toml" --manifest docs/evidence/storage-fixtures-20261030.json --output /tmp/agora-public-receipt
```

The fixture publisher must remain online. The report records the exact binary,
configuration and manifest checksums plus byte/hash agreement. `--transport mix`
tests Mix explicitly when the node configuration supports it; it never silently
falls back to direct. `scripts/check-public-storage.py` also accepts
`--config-file` for its native backend acceptance test.

## 30 October 2026 public-download correction

The native backend now passes PNG, MP4 and PDF upload, signed-reference ingestion,
public fetch and exact exported-byte verification with a fresh reader and no
manual provider connection. [Native public receipt](evidence/public-storage-native-20261030.json).
The first final-build run took 19, 71 and 9 seconds respectively; a repeat after
installation/restart took 14, 60 and 66 seconds. The MP4 is 556,240 bytes.
Public relay throughput and discovery latency are still limited; the 180-second
application transfer deadline can reject larger/slower relay transfers. These
results do not establish
large-file performance, retention, Mix transport or testnet 0.4 compatibility.
Both native test processes were on one computer. A subsequent independent GitHub-hosted reader also passed all three files: [cross-machine receipt](evidence/PUBLIC-STORAGE-20261030.md).

The patch handles constrained relay batches, known-provider admission, stale
addresses and relay renewal. Agora sends the validated MIME type and refreshes
provider announcements after every upload, including deduplicated uploads.
26 backend tests, 67 QML tests and two address-fallback/cancellation regressions
pass. The hosted workflow rebuilds the patch and checks receipt independently;
its current result is recorded in the dated verification report.

## Earlier verification

For the newer network, NAT and independent-runner checks, see
[30 October verification](evidence/NETWORK-VERIFICATION-20261030.md).
The earlier independent GitHub-hosted reader timed out before the relay and
address-fallback correction. Those failure records are retained for comparison.

The updated candidate passes image, MP4 and PDF transfer with exact hashes between
two isolated Storage nodes, including an MP4 through Basecamp, offline restart
and Store recovery. [Private integration result](evidence/private-media-20261028.json).

A separate attempt using two independently bootstrapped `logos.test` nodes on this
host failed to fetch the sample image: provider advertisement timed out and the
consumer did not receive data, including after allowing a 90-second download
inactivity window. [Public attempt](evidence/public-storage-20261028.json). Public
attachment discovery and retrieval are **not verified** here. Do not treat local
upload success or a peer count as proof another reader can fetch the file.

Native downloads allow 150 seconds without data for discovery and 180 seconds overall.
Failures preserve the source attachment and offer a retry; no corrupt download
is inserted into the local archive.
