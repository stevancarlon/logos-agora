#!/usr/bin/env python3
"""Load the installed Agora module in real Basecamp using a disposable profile."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--launcher', type=Path, required=True)
p.add_argument('--profile', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--video', action='store_true', help='Require the injected disposable inline-video probe')
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, LOGOS_USER_DIR=str(a.profile.resolve()),
           QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
result = {'passed': False, 'actualBasecampHost': True, 'crossMachineVerified': False,
          'videoPlaybackVerified': False}
with (a.output / 'basecamp.log').open('w+') as log:
    proc = subprocess.Popen([str(a.launcher.resolve()), '--user-dir', str(a.profile.resolve()),
                             '--uri=basecamp://app/logos_forum'], env=env,
                            stdout=log, stderr=log, start_new_session=True)
    try:
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            time.sleep(.5)
            log.seek(0)
            output = log.read()
            if all(marker in output for marker in (('FORUM_UI_READY', 'FORUM_STATE_READY') + (('AGORA_HOST_VIDEO_PASS', 'AGORA_VIDEO_RENDERED_FIRST_FRAME') if a.video else ()))):
                result['passed'] = True
                result['videoPlaybackVerified'] = a.video
                result['audioDeviceVerified'] = False
                result['videoFramePaintVerified'] = a.video
                break
            if proc.poll() is not None:
                result['exitCode'] = proc.returncode
                break
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=10)
(a.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
if not result['passed']:
    print((a.output / 'basecamp.log').read_text()[-18000:])
    raise SystemExit(1)
