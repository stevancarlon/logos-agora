# Network verification — 30 October 2026

## Target deployment

The public RPC at `https://testnet.lez.logos.co` responded to `checkHealth`,
`getChannelId` and `getProgramIds`. It does not expose `getVersion`.
[Recorded responses](network-target-20261030.json).

The official [endpoint table](https://github.com/logos-co/logos-docs/blob/65dea82e1455f0397c5bc14b7b192834c54acfa2/docs/get-started/testnet-endpoints.md) explicitly lists every testnet 0.4 deployment field (RPC, explorers, release and channel) as **TBD**, and identifies 0.3 as current. This is an external deployment dependency, not an inference from package versions.

The official [node guide](https://docs.logos.co/run-a-node) still identifies
the deployment as testnet v0.3. The official
[faucet network table](https://github.com/logos-co/lez-faucet#networks) identifies
the same endpoint as LEZ v0.3.1. A
[LEZ v0.4.0-rc1 source release](https://github.com/logos-blockchain/logos-execution-zone/releases/tag/v0.4.0-rc1)
exists, but its publication does not prove that this endpoint has upgraded or
that the integrated testnet 0.4 is available. A verified 0.4 deployment/configuration
is still required before claiming that prize criterion. No wallet migration,
new membership registration or paid transaction was attempted.

## Reliability checks

The acceptance harness now disables automatic connection before configuring its
private network. Previously the newly enabled application auto-connect path
raced the harness's `createNode` call and produced `Context already initialized`.
Synthetic acceptance posts remain in disposable databases on private cluster 42.

The following checks passed with the installed Delivery 0.4.0, Basecamp 0.3.2
and the current native backend:

- [Signed posts](private-delivery-20261030.json): offline queue survives process
  shutdown, the reopened sender exchanges a thread/reply with another Basecamp
  process, and a third process retrieves both through Store without duplicates.
- [Anonymous display](private-anonymous-20261030.json): the same checks pass,
  with empty author, public key and signature fields in all three databases.
- [Native media](private-media-20261030.json): PNG, MP4 and PDF exports match
  their uploaded bytes; MP4 retrieval also passes through the actual Basecamp
  bridge together with restart and Store recovery.

These are real transport tests on one computer over a private relay, not public
testnet 0.4, cross-machine Delivery, anonymity or organic-adoption evidence.

## Public attachments

The corrected native backend and patched Storage v0.5.3 now retrieve all three
public fixtures through fresh independent reader profiles, without manual peer
connections or copied blocks. [Native result](public-storage-native-20261030.json):
PNG 30,402 bytes in 18.987s, MP4 556,240 bytes in 70.802s, PDF 2,345 bytes in 9.401s.
Every signed size, SHA-256 and MIME check passed before export. Both nodes ran on
one computer; the independent hosted reader timed out, as recorded below.
A second run after installing and restarting the persistent Storage service also
passed all three files: [installed-build receipt](public-storage-installed-20261030.json).
Its timings were 13.889s, 59.513s and 66.386s. Cold discovery remains variable;
this is a correctness/recovery fix, not a low-latency claim.

The repair bounds each direct address attempt, skips Mix-only addresses in direct
mode, prefers previously successful addresses, admits known providers into full
swarms, and renews relay circuits after a single 64 KiB batch. Native uploads now
use their validated MIME type and explicitly refresh provider announcements.
The deployment retains the provider's existing identity and block store. It uses
a separately versioned patched binary, with the original official binary retained.

26 backend tests, 67 QML checks and two direct-address fallback/cancellation
regressions pass locally. [Hosted native checks](https://github.com/stevancarlon/logos-agora/actions/runs/41097790241)
and [Windows checks](https://github.com/stevancarlon/logos-agora/actions/runs/41097790362)
pass for code commit `d4cbade`. [Build/test and installation record](storage-fix-checks-20261030.json). Relay throughput and long-term file retention remain
limitations. This is not testnet 0.4 or cross-machine Delivery evidence.

### Earlier failures

A fresh Storage reader independently bootstrapped through `logos.test`, without
a direct peer connection or copied data. Before the correction, retrieval timed
out: [result](public-storage-20261030.json).

The long-running provider has peers and relay addresses, and the uploaded CIDs
have advertising enabled. Its [NAT diagnostics](storage-provider-20261030.json)
report `NotReachable`, `clientMode: true`, `portMapping: none` and
`relayRunning: true`. These observations identify a reachability concern; they
do not alone establish whether DHT discovery or relay dialing caused the timeout.
Private transfer success does not justify marking the public transfer successful.

The `Public Storage receipt` workflow runs a fresh, independent GitHub-hosted
reader using the official v0.5.3 binary and its verified release-asset hash.
It receives only public synthetic fixture CIDs, sizes and hashes. It downloads
the actual bytes through Storage public discovery, with no file upload, direct
peer connection, user credential or production database in the runner.
The [independent run](https://github.com/stevancarlon/logos-agora/actions/runs/41066916644)
bootstrapped successfully, obtained relay addresses, then timed out fetching the
first image with zero verified files. [Remote receipt](remote-storage-20261030.json).
This confirms the public retrieval failure is reproducible from a separate
machine; it does not prove its root cause. A working publicly reachable provider
or a verified relay/discovery repair is required before this gate can pass.

The separate two-computer Basecamp Delivery/restart/Store test remains unverified:
the available second Linux laptop was offline. The cloud Storage reader does not
substitute for that forum test. No peer receipt or testnet version was inferred
from a send indicator, package version, or successful local upload.

The simplified-profile test's old assumption that a 540px viewport must overflow
was also corrected to test a constrained 360px viewport. All 67 QML checks pass.

Reproduce the local native public check:

```sh
python3 scripts/check-public-storage.py --storage /absolute/path/to/patched-storage --config-file /absolute/path/to/storage-public.toml --provider-api http://127.0.0.1:18080/api/storage/v1 --output /tmp/agora-public-storage
```

For another machine, keep the provider online and run:

```sh
python3 scripts/check-storage-receipt.py --storage /absolute/path/to/patched-storage --config-file /absolute/path/to/storage-public.toml --manifest docs/evidence/storage-fixtures-20261030.json --output /tmp/agora-storage-receipt
```

The fixture manifest contains only synthetic files already distributed with the
project. It is not proof of receipt; only a successful size/hash comparison is.

## Final independent reader result

[Hosted run 41097790580](https://github.com/stevancarlon/logos-agora/actions/runs/41097790580) built the pinned patched Storage source and passed 35 swarm plus two address-fallback/cancellation tests. The independent reader discovered the provider but timed out fetching the first manifest. [Machine-readable result](public-storage-ci-final-20261030.json). This does not invalidate the recorded same-host public-relay successes, but cross-machine public retrieval remains unverified. No further success is claimed from a build or peer count alone.
