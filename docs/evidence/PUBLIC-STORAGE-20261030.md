# Independent public attachment retrieval — 30 October 2026

**Passed with relay forwarding validation.** An independent GitHub-hosted Linux
reader downloaded the original public PNG, MP4 and PDF fixture CIDs from the
persistent provider. It used an empty data directory and official fleet bootstrap
records, with no manually supplied provider connection or copied store/keys.
[Hosted run](https://github.com/stevancarlon/logos-agora/actions/runs/41111993615) ·
[Receipt](public-storage-circuit-independent-20261030.json).

| File | Bytes | Receipt time | Validation |
| --- | ---: | ---: | --- |
| PNG | 30,402 | 7.547 s | Exact size and SHA-256 |
| MP4 | 556,240 | 34.139 s | Exact size and SHA-256 |
| PDF | 2,345 | 8.610 s | Exact size and SHA-256 |

The publisher was installed at 19:03:31 UTC and remained running through the
independent test, which started at 19:08:16 UTC, and the subsequent fresh local
reader test at 19:09:30 UTC. All three files also pass in the
[initial local receipt](public-storage-circuit-local-20261030.json) and the
[delayed local repeat](public-storage-circuit-idle-repeat-20261030.json).
There was no provider restart between these receipts.

## Causes and corrections

1. DHT provider records were deduplicated by peer ID, retaining the first
   responder's addresses and discarding alternate relay addresses. The correction
   merges unique addresses per provider, capped at 32.
2. Some relays accepted reservations but did not forward connections. Renewing
   reservations alone still failed. The final correction tests the relay's actual
   HOP-to-STOP forwarding path back to the publisher before advertising it, repeats
   that check with renewal every 30 seconds, and withdraws/replaces failed paths.
   Each reservation and forwarding check has a five-second budget. The probe
   closes before application negotiation and carries no forum content.
3. The earlier provider-admission, 64 KiB relay batch and bounded address-fallback
   corrections remain in place. Identity authentication, CID/hash validation and
   the native transfer deadline are unchanged.

All three maintained patches apply to their pinned upstream sources and ship in
the 0.3.5 Linux kit. [Build instructions](../../patches/README.md) ·
[Patch application verification](storage-patch-application-20261030.json).

## Regression checks

The four-node DHT regression fails on the original dependency (11/12 pass) and
passes with address merging (12/12). Six AutoRelay tests pass, including new tests
for renewal, withdrawal after failure, and a relay that accepts reservations but
cannot forward. [DHT regression](provider-address-regression-20261030.json) ·
[Installed binary, patch hashes and relay tests](relay-circuit-regression-20261030.json).

The forum passes 26 backend and 67 QML checks on Qt 6.9.2. A caret test fixture was
corrected to use actual newlines rather than literal backslash-n text; no caret
behavior was changed. The 0.3.5 package passes official LGX validation and
[isolated Basecamp installation with corruption rejection](release-035-install-20261030.json).
Earlier native PNG/MP4/PDF signed-reference ingestion, retrieval and exact-byte
export checks remain in [native evidence](public-storage-addresses-native-20261030.json).

## Earlier failures retained

The [first address-merging remote pass](public-storage-independent-20261030.json)
was followed by a [failed remote repeat](public-storage-independent-repeat-failed-20261030.json)
and a [failed fresh local reader](public-storage-aged-provider-failed-20261030.json).
[Reservation renewal alone also failed](public-storage-renewal-only-failed-20261030.json).
These results are preserved; the current passing receipt includes the additional
forwarding validation rather than treating the first success as sufficient.

## Scope

These finite tests verify cross-machine public Storage receipt for the three
fixtures. They do not establish permanent retention, universal relay availability,
large-file throughput, cross-machine Delivery/Store messaging or testnet 0.4
compatibility. The publisher must stay online unless another Storage peer has the
content. Public relay latency remains variable. Older evidence is retained in
[the verification history](NETWORK-VERIFICATION-20261030.md).
