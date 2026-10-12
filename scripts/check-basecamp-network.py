#!/usr/bin/env python3
"""Exercise Agora's actual host bridge in an isolated, empty Basecamp profile.

Does not create posts or publish messages. This is a node-start/subscription
check, not evidence of peer receipt or Store recovery.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--basecamp', type=Path, required=True)
    parser.add_argument('--modules', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=60)
    parser.add_argument('--output', type=Path, default=ROOT / 'artifacts/network-start')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    result = {'check': 'Basecamp node start and subscription', 'passed': False,
              'peerExchangeVerified': False, 'storeRecoveryVerified': False}
    with tempfile.TemporaryDirectory(prefix='agora-network-check-') as temporary:
        profile = Path(temporary)
        (profile / 'modules').symlink_to(args.modules.resolve(), target_is_directory=True)
        subprocess.run(['python3', str(ROOT / 'scripts/install-basecamp.py'),
                        '--user-dir', str(profile)], check=True, capture_output=True)
        main_qml = profile / 'plugins/logos_forum/qml/Main.qml'
        main_qml.write_text('''import QtQuick
Item {
    ForumController {
        id: forum
        onReadyChanged: if (ready) startNode()
        onConnectionChanged: {
            console.log("AGORA_NETWORK_STATE", connection, connectionDetail)
            if (connection === "online") console.log("AGORA_NETWORK_CHECK_PASS")
        }
        onErrorChanged: if (error) console.log("AGORA_NETWORK_CHECK_ERROR", error)
    }
}
''')
        env = dict(os.environ, LOGOS_USER_DIR=str(profile),
                   LOGOS_FORUM_DATA_DIR=str(profile / 'module_data/logos_forum'),
                   QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                   LOGOS_NO_SCHEME_REGISTER='1')
        log_path = args.output / 'basecamp.log'
        with log_path.open('w+') as log:
            process = subprocess.Popen([str(args.basecamp.resolve()), '--user-dir', str(profile),
                                        '--uri=basecamp://app/logos_forum'], env=env,
                                       stdout=log, stderr=log, start_new_session=True, cwd=profile)
            try:
                deadline = time.monotonic() + args.timeout
                while time.monotonic() < deadline:
                    time.sleep(.5)
                    log.seek(0)
                    output = log.read()
                    if 'AGORA_NETWORK_CHECK_PASS' in output:
                        result['passed'] = True
                        break
                    if 'AGORA_NETWORK_CHECK_ERROR' in output or process.poll() is not None:
                        break
                result['observations'] = [line for line in output.splitlines()
                                          if 'AGORA_NETWORK_' in line]
            finally:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=10)
    (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
