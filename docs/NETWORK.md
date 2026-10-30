# Connect Agora to the public testnet

The current public network is `logos.test`. Agora publishes public discussions;
there is no central forum server. Delivery carries posts and attachment references,
while a local Logos Storage node transfers attachment files.

## Delivery

1. Install Agora and its media companion using [INSTALL.md](../INSTALL.md).
2. In Basecamp's module manager, install compatible Delivery and RLN modules.
   The verified Linux combination is Delivery **0.4.0**, RLN **0.12.0** and
   LEZ RLN **5.1.0**, running in Basecamp **0.3.2**.
3. Open Agora. It connects to Delivery automatically, starting the node if needed.
   Initial chain synchronization and membership provisioning may take several minutes.
4. If membership provisioning requests funds, use the public payer address reported
   by your local RLN provider. Request tokens on the **LEZ v0.3 testnet** with the
   [official faucet](https://github.com/logos-co/lez-faucet#networks). Legacy testnet
   tokens are on a different chain. Never share your wallet files or signing keys.
5. Fund the reported registration price plus fee reserve. On 28 October 2026 the
   quote was **182,800,000 lepta (0.1828 LEZ)**; this is a historical quote, not a
   fixed price. The faucet pays 0.1 LEZ per eligible claim and has a 24-hour
   per-recipient cooldown, so a new account may need two claims or a direct top-up.
6. Let the module finish registration. If an earlier send failed during setup,
   choose **Retry** on that post. It retains the same message ID. Connection or
   subscription alone does not mean the membership or a send is ready.

Connection is automatic by default. An existing `autoConnect: false` backend
setting is respected for local-only profiles. Queued public posts are sent after
connecting. Agora reuses an existing Delivery node without replacing another
app’s configuration. There is no separate Network settings screen.

Agora requests required mix routing when it creates its node. It does not silently
fall back to direct routing if that path fails. A shared node keeps its existing
configuration. Anonymous display and requested mix routing do not establish a
network-anonymity guarantee.

## Shared files

Follow [Storage setup](STORAGE.md). Each reader needs their own local Storage node.
A successful local upload does not establish permanent public availability.

## Verified scope

On 28 October 2026, the real welcome thread received a matching Delivery
`messageSent` event and arrived in a separate Basecamp profile through public
network discovery. The two independent databases contain the same signed envelope
hash. Both processes ran on one Linux computer; this is public-network receipt,
not a cross-machine test or evidence of community adoption.

See the [receipt evidence](evidence/public-delivery-20261028.json).

The latest LEZ RLN module's published platform coverage differs from Agora's own
four desktop builds. The combination above is verified on Linux. Do not assume
that an older Windows or Intel Mac dependency package targets the current testnet;
check the upstream catalog before enabling public publishing on those platforms.

## Prize target versus tested deployment

LP-0026 was updated on 12 October 2026 to require **Logos testnet 0.4** ([specification change](https://github.com/logos-co/lambda-prize/commit/ad608bf93f22fea4dc619f0b27bea99f98e97d58)). The receipt above uses the then-current public `logos.test` deployment and LEZ v0.3.1. Delivery module 0.4.0 is an independent version; it does not satisfy this requirement by itself.

Before submission, identify the official 0.4 deployment and compatible Delivery/RLN/LEZ packages, provision membership against that deployment if a reset requires it, then repeat send/independent receive, failed-send retry, Store recovery and attachment retrieval. Record endpoint, chain/module versions and matching message/file hashes. Preserve existing databases and signing keys through the transition. Until that evidence exists, 0.4 remains unverified.
