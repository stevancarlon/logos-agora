#!/usr/bin/env python3
"""Transfer image/video/PDF through two actual isolated Logos Storage nodes."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--storage', type=Path, required=True)
    p.add_argument('--probe', type=Path, default=ROOT / 'build/qt6.9.2-storage-probe/storage-probe')
    p.add_argument('--basecamp', type=Path)
    p.add_argument('--modules', type=Path)
    p.add_argument('--output', type=Path, default=ROOT / 'artifacts/storage-peers')
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=True)
    processes, logs = [], []
    result = {'passed': False, 'crossMachineVerified': False, 'publicNetworkVerified': False, 'files': []}
    with tempfile.TemporaryDirectory(prefix='agora-storage-peers-') as temporary:
        work = Path(temporary)
        def start(name, bootstrap=None):
            api = f'http://127.0.0.1:{port()}/api/storage/v1'
            log = (a.output / (name + '.log')).open('w')
            logs.append(log)
            command = [str(a.storage.resolve()), '--data-dir=' + str(work / name),
                       '--api-bindaddr=127.0.0.1', '--api-port=' + api.split(':')[2].split('/')[0],
                       '--listen-ip=127.0.0.1', '--nat=extip:127.0.0.1', '--num-threads=2', '--log-level=warn']
            command += ['--bootstrap-node=' + bootstrap] if bootstrap else ['--no-bootstrap-node']
            process = subprocess.Popen(command, stdout=log, stderr=log, cwd=work)
            processes.append(process)
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(name + ' exited before startup')
                try:
                    with urllib.request.urlopen(api + '/debug/info', timeout=1) as response:
                        return api, json.load(response)['spr']
                except OSError:
                    time.sleep(.2)
            raise RuntimeError(name + ' did not become ready')
        try:
            provider, spr = start('provider')
            consumer, _ = start('consumer', spr)
            if a.basecamp and a.modules:
                host = subprocess.run(['python3', str(ROOT / 'scripts/check-basecamp-peers.py'),
                    '--basecamp', str(a.basecamp.resolve()), '--modules', str(a.modules.resolve()),
                    '--provider-api', provider, '--consumer-api', consumer,
                    '--media-file', str(ROOT / 'design/agora/demo-media/playback-test.mp4'),
                    '--output', str(a.output / 'basecamp')], capture_output=True, text=True, timeout=240)
                (a.output / 'basecamp-check.log').write_text(host.stdout + host.stderr)
                host.check_returncode()
                result['basecamp'] = json.loads((a.output / 'basecamp/result.json').read_text())
            for name in ('workshop-diagram.png', 'playback-test.mp4', 'workshop-plan.pdf'):
                completed = subprocess.run([str(a.probe.resolve()), provider, consumer,
                    str(ROOT / 'design/agora/demo-media' / name)], capture_output=True, text=True, timeout=210)
                (a.output / (name + '.log')).write_text(completed.stdout + completed.stderr)
                completed.check_returncode()
                result['files'].append(json.loads(completed.stdout))
            result['passed'] = True
        except Exception as error:
            result['error'] = str(error)
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
            for process in processes:
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait(timeout=10)
            for log in logs:
                log.close()
    (a.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
