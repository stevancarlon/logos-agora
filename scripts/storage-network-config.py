#!/usr/bin/env python3
"""Generate standalone Storage configuration from the official public fleet.

Does not start a node, change identities, upload files or claim connectivity.
The generated TOML is accepted by Storage's --config-file option.
"""
import argparse
import datetime
import hashlib
import ipaddress
import json
from pathlib import Path
import urllib.request

FLEET_URL = 'https://fleets.logos.co/logos-test/storage-network.json'


def configuration(fleet, mix=False):
    if not isinstance(fleet, list) or not 1 <= len(fleet) <= 100:
        raise ValueError('Expected a nonempty official fleet list')
    records, relays, proxies = [], [], []
    for node in fleet:
        spr = node.get('spr', '')
        if not isinstance(spr, str) or not spr.startswith('spr:') or len(spr) > 16384:
            raise ValueError('Fleet entry has no valid signed peer record')
        if spr not in records:
            records.append(spr)
        if mix and node.get('role') == 'mp':
            address = ipaddress.ip_address(node['address'])
            port = node['port']
            if type(port) is not int or not 1 <= port <= 65535:
                raise ValueError('Invalid Mix relay port')
            relay = {key: node[key] for key in ('peerId', 'mixPubKey', 'libp2pPubKey')}
            if not all(isinstance(v, str) and 0 < len(v) <= 512 for v in relay.values()):
                raise ValueError('Invalid Mix relay identity')
            relay['multiAddr'] = f'/ip{address.version}/{address}/tcp/{port}'
            relays.append(relay)
            proxies.append(spr)
    config = {'network': 'logos.test', 'bootstrap-node': records}
    if mix:
        if len(relays) < 3:
            raise ValueError('The fleet has fewer than three Mix relays')
        config.update({'mix-enabled': True, 'dht-mix-proxy': proxies,
                       'mix-pool-json': json.dumps({'version': 1, 'relays': relays})})
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mix', action='store_true', help='Also configure the official Mix relay pool and DHT proxies')
    args = parser.parse_args()
    request = urllib.request.Request(FLEET_URL, headers={'User-Agent': 'agora-storage-config/1.0'})
    with urllib.request.urlopen(request, timeout=30) as response:
        raw = response.read(1024 * 1024 + 1)
    if len(raw) > 1024 * 1024:
        raise ValueError('Fleet response exceeds 1 MiB')
    config = configuration(json.loads(raw), args.mix)
    # Refuse replacement: callers can inspect a new file before switching nodes.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as output:
        for key, value in config.items():
            output.write(f'{key} = {json.dumps(value)}\n')
    print(json.dumps({'config': str(args.output.resolve()), 'source': FLEET_URL,
                      'fetchedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      'fleetSha256': hashlib.sha256(raw).hexdigest(),
                      'bootstrapRecords': len(config['bootstrap-node']),
                      'mixEnabled': args.mix, 'connectivityVerified': False}, indent=2))


if __name__ == '__main__':
    main()
