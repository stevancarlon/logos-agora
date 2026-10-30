# Independent public attachment retrieval — 30 October 2026

**Passed.** An independent GitHub-hosted Linux reader downloaded the original
public fixture CIDs from the persistent provider on the developer's computer.
The reader started with an empty data directory, used current official fleet
bootstrap records, and made no manual peer connection. No provider store or
signing keys were copied. [Hosted run](https://github.com/stevancarlon/logos-agora/actions/runs/41107109568) · [Receipt](public-storage-independent-20261030.json).

| File | Bytes | Receipt time | Validation |
| --- | ---: | ---: | --- |
| PNG | 30,402 | 9.080 s | Exact signed size and SHA-256 |
| MP4 | 556,240 | 63.183 s | Exact signed size and SHA-256 |
| PDF | 2,345 | 9.210 s | Exact signed size and SHA-256 |

## Cause and correction

Provider records are deduplicated by peer ID. The upstream DHT collector retained
only the first responder's address list, discarding alternate addresses reported
by later responders. Public traces showed expired relay addresses in some replies
and current addresses in others. Readers could therefore repeatedly dial expired
relays even though discovery had received a working address.

The nim-libp2p correction merges unique addresses for each provider, capped at 32.
It preserves peer identity authentication and all attachment integrity checks.
The earlier relay-size and connection-fallback corrections remain in place.
Both pinned dependency patches and build instructions are in [patches](../../patches/README.md).

The new four-node regression fails on the original dependency (11/12 tests pass)
and passes with the correction (12/12). [Regression evidence](provider-address-regression-20261030.json).
The native forum also passes PNG/MP4/PDF upload, signed-reference ingestion,
public retrieval and exact exported-byte verification, with times of 10.821,
62.784 and 14.222 seconds. [Native result](public-storage-addresses-native-20261030.json).
26 backend and 67 QML tests pass on Qt 6.9.2.

## Scope

This verifies cross-machine public Storage receipt for these fixtures. It does
not establish cross-machine Delivery/Store messaging, testnet 0.4 compatibility,
permanent retention or large-file throughput. Public relay latency remains
variable; the 556 KB video took approximately one minute. The native 180-second
transfer deadline and integrity checks remain unchanged. Older failures are
retained in [the verification history](NETWORK-VERIFICATION-20261030.md).
