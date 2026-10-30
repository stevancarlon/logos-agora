# Sharing media through Logos Storage

Agora 0.3 supports images, video and PDFs through Logos Storage. Text and signed
attachment references travel through Delivery; file bytes travel through Storage.
There is no central forum server. Each participant uses a local Storage node.

## Connect a node

Use the official [Logos Storage implementation](https://github.com/logos-storage/logos-storage-nim).
The tested binary is v0.5.3 on Linux x86_64. With its `storage` executable installed,
run a node with a persistent directory and a loopback-only API:

```sh
storage --data-dir="$HOME/.local/share/AgoraStorage" --api-bindaddr=127.0.0.1 --api-port=8080
```

Keep this process running. Node discovery/bootstrap and network reachability must
be configured for the network your participants use. Public-network availability
has not yet been verified for this release. The automatic tests use two private,
loopback-connected nodes and no external bootstrap services.

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
`agora-storage.service`, Storage v0.5.3, and port `18080`; its API is
`http://127.0.0.1:18080/api/storage/v1`. Check it with
`systemctl --user status agora-storage.service`. The service starts at user login.
This is a separate official Storage process because Agora's HTTP integration
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

## 28 October 2026 verification

For the newer network, NAT and independent-runner checks, see
[30 October verification](evidence/NETWORK-VERIFICATION-20261030.md).
The independent GitHub-hosted reader also timed out; public attachment retrieval
is still a failing acceptance gate, while private native transfer passes.

The updated candidate passes image, MP4 and PDF transfer with exact hashes between
two isolated Storage nodes, including an MP4 through Basecamp, offline restart
and Store recovery. [Private integration result](evidence/private-media-20261028.json).

A separate attempt using two independently bootstrapped `logos.test` nodes on this
host failed to fetch the sample image: provider advertisement timed out and the
consumer did not receive data, including after allowing a 90-second download
inactivity window. [Public attempt](evidence/public-storage-20261028.json). Public
attachment discovery and retrieval are **not verified** here. Do not treat local
upload success or a peer count as proof another reader can fetch the file.

Downloads allow 90 seconds without data for discovery and 180 seconds overall.
Failures preserve the source attachment and offer a retry; no corrupt download
is inserted into the local archive.
