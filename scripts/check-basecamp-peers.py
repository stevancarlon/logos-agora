#!/usr/bin/env python3
"""Two isolated Basecamp processes exchanging real Agora envelopes over loopback.
Private relay test: no public discovery, no mix/anonymity claim, no user data.
"""
import argparse
import json
import hashlib
import os
from pathlib import Path
import re
import signal
import socket
import sqlite3
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--basecamp', type=Path, required=True)
    p.add_argument('--modules', type=Path, required=True)
    p.add_argument('--timeout', type=int, default=90)
    p.add_argument('--media-file', type=Path)
    p.add_argument('--provider-api', default='')
    p.add_argument('--consumer-api', default='')
    p.add_argument('--anonymous', action='store_true', help='Test anonymous display envelopes, not network anonymity')
    p.add_argument('--output', type=Path, default=ROOT / 'artifacts/network-peers')
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=True)
    # Private cluster 42, loopback peers and discovery disabled keep this off
    # public networks while exercising the exact production content topic.
    topic = '/logos-forum/1/commons/json'
    processes = []
    logs = []
    result = {'passed': False, 'transport': 'private loopback relay',
              'crossMachineVerified': False, 'mixRoutingVerified': False,
              'storeRecoveryVerified': False, 'offlineRestartVerified': False, 'topic': topic,
              'identityMode': 'anonymous' if a.anonymous else 'alias'}
    with tempfile.TemporaryDirectory(prefix='agora-peer-check-') as temporary:
        def start(role, peers, profile_name=None):
            profile = Path(temporary) / (profile_name or role)
            profile.mkdir(exist_ok=True)
            if not (profile / 'modules').exists():
                (profile / 'modules').symlink_to(a.modules.resolve(), target_is_directory=True)
            subprocess.run(['python3', str(ROOT / 'scripts/install-basecamp.py'), '--user-dir', str(profile)], check=True, capture_output=True)
            qml = profile / 'plugins/logos_forum/qml'
            controller = qml / 'ForumController.qml'
            controller.write_text(controller.read_text().replace('/logos-forum/1/commons/json', topic))
            config = dict(listenAddress='127.0.0.1', tcpPort=port(), clusterId=42,
                          numShardsInNetwork=1, relay=True, store=True, filter=False,
                          lightpush=False, peerExchange=False, discv5Discovery=False,
                          nat='none', reliabilityEnabled=True, staticnodes=peers)
            template = (ROOT / 'native/tests/network/Peer.qml').read_text()
            template = template.replace('CONFIG_JSON', json.dumps(json.dumps(config))).replace('ROLE_JSON', json.dumps(role)).replace('STORE_PEER_JSON', json.dumps(peers[0] if peers else ''))
            template = template.replace('MEDIA_FILE_JSON', json.dumps(a.media_file.resolve().as_uri() if a.media_file else ''))
            template = template.replace('STORAGE_API_JSON', json.dumps(a.provider_api if role in ('prepare', 'sender') else a.consumer_api))
            template = template.replace('TEST_MODE_JSON', json.dumps('anonymous' if a.anonymous else 'alias'))
            (qml / 'Main.qml').write_text(template)
            env = dict(os.environ, LOGOS_USER_DIR=str(profile),
                       LOGOS_FORUM_DATA_DIR=str(profile / 'module_data/logos_forum'),
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', LOGOS_NO_SCHEME_REGISTER='1')
            log = (a.output / (role + '.log')).open('w+')
            logs.append(log)
            process = subprocess.Popen([str(a.basecamp.resolve()), '--user-dir', str(profile),
                                        '--uri=basecamp://app/logos_forum'], env=env,
                                       stdout=log, stderr=log, start_new_session=True, cwd=profile)
            processes.append(process)
            return log

        def read(log):
            log.seek(0)
            return log.read()

        def stop(process):
            if process.poll() is not None:
                return
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)

        def posts(profile):
            path = Path(temporary) / profile / 'module_data/logos_forum/forum.sqlite'
            with sqlite3.connect(f'file:{path}?mode=ro', uri=True) as db:
                return db.execute('SELECT id,thread,status FROM posts ORDER BY id').fetchall()

        try:
            prepared = start('prepare', [], 'sender')
            deadline = time.monotonic() + 30
            while 'AGORA_OFFLINE_QUEUED' not in read(prepared):
                if time.monotonic() >= deadline or processes[-1].poll() is not None:
                    raise RuntimeError('Offline post was not prepared')
                time.sleep(.5)
            stop(processes[-1])
            queued = posts('sender')
            if len(queued) != 1 or queued[0][2] != 'queued':
                raise RuntimeError('Offline post did not survive process shutdown')
            receiver = start('receiver', [])
            deadline = time.monotonic() + a.timeout
            addresses = None
            while time.monotonic() < deadline:
                output = read(receiver)
                match = re.search(r'AGORA_PEER_ADDRESSES (.*)', output)
                if match:
                    addresses = json.loads(match.group(1))
                    if isinstance(addresses, str):
                        addresses = addresses.split(',') if addresses.startswith('/') else json.loads(addresses)
                    break
                if 'AGORA_PEER_ERROR' in output:
                    raise RuntimeError('Receiver failed; inspect receiver.log')
                time.sleep(.5)
            if not addresses:
                raise RuntimeError('No receiver addresses; inspect receiver.log')
            if isinstance(addresses, dict):
                addresses = addresses.get('multiaddresses', addresses.get('listenAddresses', []))
            sender = start('sender', addresses)
            while time.monotonic() < deadline:
                received = re.search(r'AGORA_PEER_RECEIVED ([a-f0-9]{64})', read(receiver))
                reply = re.search(r'AGORA_PEER_REPLY ([a-f0-9]{64})', read(sender))
                media_ready = not a.media_file or 'AGORA_ATTACHMENT_FETCHED' in read(receiver)
                if received and reply and media_ready:
                    if received.group(1) != queued[0][0]:
                        raise RuntimeError('Delivered message differs from persisted offline post')
                    result.update(passed=True, receivedThread=received.group(1), receivedReply=reply.group(1))
                    result['offlineRestartVerified'] = True
                    break
                if any('AGORA_PEER_ERROR' in read(log) for log in logs):
                    raise RuntimeError('Peer failed; inspect logs')
                time.sleep(.5)
            if not result['passed']:
                result['error'] = 'Timed out before both peers persisted the exchange'
            else:
                history = start('history', addresses)
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    output = read(history)
                    if 'AGORA_STORE_RECOVERED' in output:
                        result['storeRecoveryVerified'] = True
                        break
                    if 'AGORA_PEER_ERROR' in output:
                        break
                    time.sleep(.5)
                if not result['storeRecoveryVerified']:
                    result.update(passed=False, error='Live exchange passed; Store recovery did not complete')
                else:
                    expected = sorted([result['receivedThread'], result['receivedReply']])
                    for name in ('sender', 'receiver', 'history'):
                        rows = posts(name)
                        if sorted(row[0] for row in rows) != expected:
                            raise RuntimeError(f'{name} persisted unexpected or duplicate posts')
                        path = Path(temporary) / name / 'module_data/logos_forum/forum.sqlite'
                        with sqlite3.connect(f'file:{path}?mode=ro', uri=True) as db:
                            for mode, author, public_key, wire in db.execute('SELECT mode,author,pub,wire FROM posts'):
                                signature = json.loads(wire)['signature']
                                if a.anonymous:
                                    if mode != 'anonymous' or author or public_key or signature:
                                        raise RuntimeError(f'{name} retained identity fields in anonymous posts')
                                elif mode != 'alias' or not public_key or not signature:
                                    raise RuntimeError(f'{name} is missing signed alias fields')
                    result['independentDatabasesVerified'] = True
                    result['identityModeVerified'] = True
                    if a.media_file:
                        path = Path(temporary) / 'receiver/module_data/logos_forum/forum.sqlite'
                        with sqlite3.connect(f'file:{path}?mode=ro', uri=True) as db:
                            downloaded = db.execute("SELECT path FROM attachments WHERE post=?", (result['receivedThread'],)).fetchone()
                        if not downloaded or hashlib.sha256(Path(downloaded[0]).read_bytes()).digest() != hashlib.sha256(a.media_file.read_bytes()).digest():
                            raise RuntimeError('Basecamp attachment bytes do not match uploaded media')
                        result['basecampMediaTransferVerified'] = True
        except Exception as error:
            result['passed'] = False
            result['error'] = str(error)
        finally:
            for process in processes:
                stop(process)
            for log in logs:
                log.close()
    (a.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
