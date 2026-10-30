# RLN state-selection correction

`logos-rln-0.12.0-state-candidates.patch` targets
[logos-rln-modules d9f8b3d5ff93f6fd6fb363f5689098c07e81ac47](https://github.com/logos-co/logos-rln-modules/tree/d9f8b3d5ff93f6fd6fb363f5689098c07e81ac47).

The startup membership-state query counts erased legacy records alongside a
usable replacement and returns `ambiguous_selection`. The patch prefers usable
candidates after existing scope/quarantine filtering, matching proof selection.
It retains ambiguity for multiple usable credentials and retains diagnostics
when none are usable. The chosen record still undergoes the existing live
registry read. No keys, allocation ledgers, or credential files are modified.

Apply in that dependency checkout with `git apply` and rebuild/package using
its documented toolchain. This patch is **not installed in the shared Basecamp
RLN binary**. Agora's publishing-readiness guard is independent of it and safely
pauses its outbox on an ambiguous or otherwise unusable credential.

The four pure selection regressions can run without the host SDK:

```sh
rustc --test logos-rln-module/rust-lib/src/state_candidates.rs -o /tmp/rln-selection-tests
/tmp/rln-selection-tests
```

These passed locally; they do not replace the dependency's full build,
registry integration tests, or release validation. The full module build needs
the upstream generated provider, SDK, module builder, and protocol libraries.

# Storage public-download correction

`logos-storage-0.5.3-public-download.patch` targets the official Storage v0.5.3
source commit `56854f4ebce0cfe68e3557d1be21b758ac62ae0c`.

A download initially samples up to 16 connected peers with unknown availability.
When those fill its swarm, the upstream admission check rejects subsequently
advertised providers. After a relay disconnect, replacement unknown peers can
also prevent the original provider from rejoining. The patch admits a known
provider by replacing an unknown peer, while retaining the capacity limit and
explicit bans. It does not evict known providers to admit unknown peers.

The default 128 KiB payload batch also exceeds a default 128 KiB relay allowance
once framing/proofs are added. The patch requests 64 KiB target batches, leaving
protocol decoding limits unchanged. This favors progress through constrained
relays over maximum direct-connection throughput. Existing 64 KiB Agora upload
blocks fit individually; larger custom block sizes are outside this workaround's
relay-size guarantee.

The direct download scheduler queries discovered providers first. For relayed
peers it allows one batch at a time, retires the circuit after the verified
batch, and reconnects using the already-discovered provider addresses while
more blocks are needed. This avoids both exhausting the relay allowance with
concurrent batches and repeating DHT discovery for every block. Reachable direct
peers retain their normal connections and pipelining.

Direct provider dials skip Mix-only addresses and allow eight seconds per
address. An expired relay therefore cannot consume the full manifest timeout
before the next address is tried, with a 25-second total connection budget.
Previously successful addresses are preferred for subsequent circuits. Manifest
timeouts retire stale connections
before retrying. Regression tests cover an unresponsive first address followed
by a working peer, and cancellation during connection setup.

The `agoraRelayOnly` build option disables automatic NAT hole punching, whose
connection attempts delay the usable relay on this deployment. Ordinary direct
connections remain supported. This is an Agora-maintained dependency patch, not
an official Storage release or a testnet-version claim.

Build and test in a separate checkout (Nim 2.2.10, C/C++ compiler, make, CMake):

```sh
git checkout 56854f4ebce0cfe68e3557d1be21b758ac62ae0c
git apply /absolute/path/to/logos-agora/patches/logos-storage-0.5.3-public-download.patch
git -C vendor/nim-libp2p apply /absolute/path/to/logos-agora/patches/logos-libp2p-provider-addresses.patch
git -C vendor/nim-libp2p apply /absolute/path/to/logos-agora/patches/logos-libp2p-relay-renewal.patch
make USE_SYSTEM_NIM=1 NIM_PARAMS="-d:release -d:agoraRelayOnly" -j2
./env.sh nim c -r -d:release --out:build/testswarm tests/storage/blockexchange/engine/testswarm.nim
./env.sh nim c -r -d:release --out:build/testdirectconnect tests/storage/testdirectconnect.nim
```

On 30 October, the patched reader fetched PNG, MP4 and PDF from a separate
provider through public discovery and relays with exact byte/hash verification.
Both nodes were on the same computer; this does not establish cross-machine
receipt. Final native checks passed all three files twice, including after
installing/restarting the persistent provider. The 556,240-byte MP4 took 60–71
seconds; the PDF varied from 9 to 66 seconds. Large-file throughput, cold discovery
latency and public retention remain limitations. The 35 swarm regressions,
two address-fallback/cancellation tests and isolated native PNG/MP4/PDF transfers
also passed. See [the dated report](../docs/evidence/NETWORK-VERIFICATION-20261030.md).

The `Patched Storage public receipt` workflow independently builds this source
and patch, loads current official fleet records, runs swarm regressions, and
retrieves the public fixture CIDs. It does not copy the provider's store or keys.
A successful build alone is not receipt evidence: all fixture downloads and
checksums must pass as well.

## Provider address preservation

`logos-libp2p-provider-addresses.patch` targets Storage v0.5.3's pinned
nim-libp2p commit `9281a6d35671af70417d0d1330ce64adb3e39fdd`.
Apply it inside `vendor/nim-libp2p` in addition to the Storage patch above.

Public DHT peers can cache different relay addresses for the same provider.
The upstream provider set compares records by peer ID, so the first response
wins and subsequent responses containing working relay addresses are discarded.
The correction merges unique addresses for each provider, retaining at most 32.
It does not alter provider identity checks, CID verification or transport
security. A real four-node DHT regression checks that both sets of addresses
survive discovery while the provider itself remains deduplicated.

Run the dependency regression from the Storage checkout:

```sh
USE_SYSTEM_NIM=1 ./env.sh nim c -r -d:release --warningAsError:UnusedImport:off --out:build/test_get_providers vendor/nim-libp2p/tests/libp2p/kademlia/test_get_providers.nim
```

The unused-import override is needed by the upstream test logger under the
Storage checkout's compiler configuration; it does not disable assertions.
Remote receipt results are recorded separately from build/regression results.

## Relay renewal

`logos-libp2p-relay-renewal.patch` applies to the same pinned nim-libp2p
revision. Relay reservations can remain valid longer than the idle TCP/NAT
connection that carries incoming circuits. Renewing every 30 seconds checks
the path as well as the reservation; each renewal retains the existing
five-second timeout. Failed renewals withdraw their addresses from PeerInfo,
disconnect the unusable path and let the existing backoff choose a replacement.
The patch does not restart Storage or change stored files, keys or identities.

Before advertising a reservation, the service also tests a circuit through
that relay back to itself. It closes the probe before application negotiation;
no forum content or signing key is sent. This checks actual forwarding, which
can fail even when reservation renewals succeed. The check has a five-second
budget and is repeated with each renewal.

Three regressions use real relay/client switches to verify renewal before expiry,
address withdrawal after a failed renewal, and rejection of a relay that accepts
reservations but cannot forward a circuit. Run alongside the upstream
AutoRelay tests:

```sh
USE_SYSTEM_NIM=1 ./env.sh nim c -r -d:release --warningAsError:UnusedImport:off --out:build/test_autorelay vendor/nim-libp2p/tests/libp2p/services/test_autorelay.nim
```

Independent receipt must also be checked after the publisher has been idle;
a download immediately after restart is insufficient evidence of reliability.
