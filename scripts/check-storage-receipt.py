#!/usr/bin/env python3
"""Fetch public test fixtures from a fresh Storage node; never upload file bytes.

Run on an independent computer. The report records byte/hash agreement, not
Delivery receipt, Basecamp UI behavior, network anonymity or testnet 0.4 support.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time
import urllib.request


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--storage', type=Path, required=True)
    p.add_argument('--manifest', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    fixtures = json.loads(a.manifest.read_text())['files']
    if not 1 <= len(fixtures) <= 4:
        p.error('Expected one to four public test fixtures')
    for f in fixtures:
        if (not re.fullmatch(r'z[1-9A-HJ-NP-Za-km-z]{20,120}', f['cid'])
                or not re.fullmatch(r'[a-f0-9]{64}', f['sha256'])
                or type(f['bytes']) is not int or not 0 < f['bytes'] <= 64 * 1024 * 1024):
            p.error('Invalid fixture CID, digest or size')
    a.output.mkdir(parents=True, exist_ok=True)
    result = {'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'networkPreset': 'logos.test', 'passed': False,
              'testnet04Verified': False, 'manualPeerConnection': False,
              'scope': 'Public Storage byte/hash receipt; no Delivery or Basecamp UI claim',
              'githubRun': os.environ.get('GITHUB_RUN_ID'),
              'storageVersion': subprocess.check_output([str(a.storage), '--version'], text=True).strip(),
              'storageSha256': hashlib.sha256(a.storage.read_bytes()).hexdigest(),
              'manifestSha256': hashlib.sha256(a.manifest.read_bytes()).hexdigest(),
              'files': []}
    with tempfile.TemporaryDirectory(prefix='agora-storage-receipt-') as work:
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        api = f'http://127.0.0.1:{port}/api/storage/v1'
        with (a.output / 'storage.log').open('w') as log:
            process = subprocess.Popen([str(a.storage.resolve()), '--data-dir=' + work,
                '--api-bindaddr=127.0.0.1', '--api-port=' + str(port), '--network=logos.test',
                '--num-threads=2', '--log-level=debug', '--log-format=nocolors'], stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 90
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise RuntimeError('Storage reader exited during startup')
                    try:
                        with urllib.request.urlopen(api + '/debug/info', timeout=3) as response:
                            node = json.load(response)
                        if node.get('addrs') and node.get('table', {}).get('nodes'):
                            result['readerPeerId'] = node['id']
                            result['readerAddresses'] = node['addrs']
                            break
                    except OSError:
                        pass
                    time.sleep(1)
                else:
                    raise RuntimeError('No public peers or reachable address within 90 seconds')
                for fixture in fixtures:
                    started = time.monotonic()
                    digest = hashlib.sha256()
                    count = 0
                    with urllib.request.urlopen(api + '/data/' + fixture['cid'] +
                                                '/network/stream?advertise=false', timeout=90) as stream:
                        while True:
                            chunk = stream.read(65536)
                            if not chunk:
                                break
                            count += len(chunk)
                            if count > fixture['bytes'] or time.monotonic() - started > 180:
                                raise RuntimeError('Download exceeded signed size or time limit')
                            digest.update(chunk)
                    if count != fixture['bytes'] or digest.hexdigest() != fixture['sha256']:
                        raise RuntimeError('Downloaded bytes do not match fixture manifest')
                    result['files'].append(dict(fixture, seconds=round(time.monotonic() - started, 3), passed=True))
                    print('Verified', fixture['name'], count, flush=True)
                result['passed'] = True
            except Exception as error:
                result['error'] = str(error)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=10)
    (a.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
