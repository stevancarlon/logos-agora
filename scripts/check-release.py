#!/usr/bin/env python3
"""Install an extracted release kit and load its real GUI in disposable Basecamp."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tarfile
import tempfile
import time


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive', type=Path, required=True)
    p.add_argument('--qt', type=Path, required=True)
    p.add_argument('--basecamp', type=Path, required=True, help='Original unmodified AppImage')
    p.add_argument('--modules', type=Path, required=True)
    p.add_argument('--output', type=Path, default=Path('artifacts/release-check'))
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=True)
    result = {'passed': False, 'cleanOSVerified': False, 'isolatedProfile': True}
    with tempfile.TemporaryDirectory(prefix='agora-release-check-') as temporary:
        work = Path(temporary)
        with tarfile.open(a.archive) as archive:
            archive.extractall(work, filter='data')
        bundle = next(work.glob('agora-*'))
        installer = bundle / 'scripts/install-release.py'
        # A modified file must fail verification before any install action.
        readme = bundle / 'README.md'
        original = readme.read_bytes()
        readme.write_bytes(original + b'\nCORRUPTION TEST\n')
        corrupt = subprocess.run([sys.executable, str(installer), '--verify-only'], capture_output=True, text=True)
        readme.write_bytes(original)
        if corrupt.returncode == 0 or 'checksum mismatch' not in corrupt.stderr:
            raise RuntimeError('Installer accepted a modified release')
        profile, runtime, launcher = work / 'profile', work / 'runtime', work / 'launch-agora'
        profile.mkdir()
        (profile / 'modules').symlink_to(a.modules.resolve(), target_is_directory=True)
        command = [sys.executable, str(installer), '--qt', str(a.qt.resolve()),
                   '--appimage', str(a.basecamp.resolve()), '--user-dir', str(profile),
                   '--runtime-dir', str(runtime), '--launcher', str(launcher), '--no-desktop']
        installed = subprocess.run(command, capture_output=True, text=True)
        (a.output / 'install.log').write_text(installed.stdout + installed.stderr)
        installed.check_returncode()
        env = dict(os.environ, LOGOS_USER_DIR=str(profile),
                   LOGOS_FORUM_DATA_DIR=str(profile / 'module_data/logos_forum'),
                   QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
        for name in ('QML_IMPORT_PATH', 'QML2_IMPORT_PATH', 'QT_PLUGIN_PATH', 'LD_LIBRARY_PATH'):
            env.pop(name, None)
        with (a.output / 'basecamp.log').open('w+') as log:
            process = subprocess.Popen([str(launcher), '--user-dir', str(profile),
                                        '--uri=basecamp://app/logos_forum'], env=env, cwd=profile,
                                       stdout=log, stderr=log, start_new_session=True)
            try:
                deadline = time.monotonic() + 45
                while time.monotonic() < deadline:
                    time.sleep(.5)
                    log.seek(0)
                    output = log.read()
                    if 'FORUM_STATE_READY' in output and 'FORUM_UI_READY' in output:
                        result.update(passed=True, corruptReleaseRejected=True, compiledOnInstall=False)
                        break
                    if process.poll() is not None:
                        break
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=10)
    (a.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
