#!/usr/bin/env python3
"""Exercise real Basecamp with staged Agora dependencies and an isolated profile."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

p = argparse.ArgumentParser(description=__doc__)
for name in ('host-bin', 'runtime-dir', 'profile', 'output'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--video', action='store_true', help='Require the injected disposable inline-video probe')
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
env = dict(os.environ)
for name in ('QML2_IMPORT_PATH', 'QT_QML_IMPORT_PATH', 'QT_PLUGIN_PATH', 'QML_IMPORT_PATH'):
    env.pop(name, None)
system = Path(os.environ['SystemRoot'])
env.update(PATH=os.pathsep.join(map(str, [a.host_bin, a.runtime_dir / 'bin', system / 'System32', system])),
           LOGOS_USER_DIR=str(a.profile), LOGOS_NO_SCHEME_REGISTER='1',
           QT_PLUGIN_PATH=str(a.runtime_dir / 'plugins'), QML_IMPORT_PATH=str(a.runtime_dir / 'qml'),
           QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
           QT_LOGGING_RULES='logos.viewhost.debug=true')
result = {'passed': False, 'actualBasecampHost': True, 'videoPlaybackVerified': False,
          'crossMachineVerified': False, 'buildToolchainRemovedFromPath': True}
probe = subprocess.run([sys.executable, '-c',
    'import ctypes,sys; ctypes.WinDLL(sys.argv[1], winmode=8); print("Native backend DLL dependencies resolved")',
    str(a.profile / 'plugins/logos_forum/forum_backend.dll')], env=env, capture_output=True, timeout=15)
(a.output / 'dll-load.log').write_bytes(probe.stdout + probe.stderr)
result['backendDllLoadPassed'] = probe.returncode == 0
with (a.output / 'basecamp.log').open('w+', encoding='utf-8', errors='replace') as log:
    proc = subprocess.Popen([str(a.host_bin / 'LogosBasecamp.exe'), '--user-dir', str(a.profile),
                             '--uri=basecamp://app/logos_forum'], env=env, stdout=log, stderr=log)
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
        subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], capture_output=True)
        proc.wait(timeout=10)
(a.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
if not result['passed']:
    print((a.output / 'basecamp.log').read_text(encoding='utf-8', errors='replace')[-18000:])
    raise SystemExit(1)
