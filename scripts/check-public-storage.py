#!/usr/bin/env python3
"""Check public Storage discovery with the native attachment backend.

Starts a fresh reader and uses an existing, independently bootstrapped local
provider. No direct peer connection, copied blocks, or forum messages are used.
Both nodes are on this host: this never establishes cross-machine exchange.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def info(api):
    with urllib.request.urlopen(api + '/debug/info', timeout=3) as response:
        node = json.load(response)
    return {'peerId': node.get('id'), 'addresses': node.get('addrs', []),
            'discoveredPeers': len(node.get('table', {}).get('nodes', []))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--storage', type=Path, required=True)
    parser.add_argument('--provider-api', default='http://127.0.0.1:18080/api/storage/v1')
    parser.add_argument('--probe', type=Path, default=ROOT / 'build/qt6.9.2-storage-probe/storage-probe')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    result = {'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'networkPreset': 'logos.test', 'testnet04Verified': False,
              'sameMachine': True, 'crossMachineVerified': False,
              'manualPeerConnection': False, 'passed': False, 'files': []}
    binary = args.storage.resolve(strict=True)
    result['storageSha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
    result['storageVersion'] = subprocess.check_output([str(binary), '--version'], text=True).strip()
    result['probeSha256'] = hashlib.sha256(args.probe.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='agora-public-reader-') as temporary:
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        consumer = f'http://127.0.0.1:{port}/api/storage/v1'
        with (args.output / 'consumer.log').open('w') as log:
            process = subprocess.Popen([str(binary), '--data-dir=' + temporary,
                '--api-bindaddr=127.0.0.1', '--api-port=' + str(port),
                '--network=logos.test', '--num-threads=2', '--log-level=info',
                '--log-format=nocolors'], stdout=log, stderr=log)
            try:
                result['provider'] = info(args.provider_api)
                deadline = time.monotonic() + 90
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise RuntimeError('Reader exited during startup')
                    try:
                        reader = info(consumer)
                        if reader['addresses'] and reader['discoveredPeers']:
                            result['consumer'] = reader
                            break
                    except OSError:
                        pass
                    time.sleep(1)
                else:
                    raise RuntimeError('Reader did not acquire public peers and a reachable address')
                for name in ('workshop-diagram.png', 'playback-test.mp4', 'workshop-plan.pdf'):
                    started = time.monotonic()
                    run = subprocess.run([str(args.probe.resolve()), args.provider_api,
                        consumer, str(ROOT / 'design/agora/demo-media' / name)],
                        capture_output=True, text=True, timeout=210, env=dict(os.environ))
                    (args.output / (name + '.log')).write_text(run.stdout + run.stderr)
                    if run.returncode:
                        raise RuntimeError(name + ': ' + run.stderr.strip()[-1200:])
                    receipt = json.loads(run.stdout)
                    receipt['seconds'] = round(time.monotonic() - started, 3)
                    result['files'].append(receipt)
                    print(name, receipt['passed'], receipt['seconds'], flush=True)
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
    (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
