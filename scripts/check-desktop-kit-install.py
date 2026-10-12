#!/usr/bin/env python3
"""Verify corruption rejection and install an actual desktop kit in a test profile."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

p = argparse.ArgumentParser(description=__doc__)
for name in ('archive', 'qt', 'profile', 'runtime-dir', 'launcher', 'output'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--app', type=Path)
p.add_argument('--host-bin', type=Path)
a = p.parse_args()
if not (a.profile / '.agora-disposable-profile').is_file():
    p.error('Installation checks require a marked disposable profile')
if not a.app and not a.host_bin:
    p.error('Select --app (Mac) or --host-bin (Windows)')
a.output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='agora-kit-check-') as temporary:
    work = Path(temporary)
    with tarfile.open(a.archive) as archive:
        archive.extractall(work, filter='data')
    kits = list(work.glob('agora-*'))
    if len(kits) != 1:
        raise SystemExit('Expected exactly one release kit')
    kit = kits[0]
    installer = kit / 'scripts/install-release.py'
    readme = kit / 'README.md'
    original = readme.read_bytes()
    readme.write_bytes(original + b'\nCORRUPTION CHECK\n')
    corrupt = subprocess.run([sys.executable, str(installer), '--verify-only'], capture_output=True)
    readme.write_bytes(original)
    if corrupt.returncode == 0 or b'checksum mismatch' not in corrupt.stderr:
        raise SystemExit('Corrupted kit was not rejected')
    command = [sys.executable, str(installer), '--qt', str(a.qt.resolve()),
               '--user-dir', str(a.profile.resolve()), '--runtime-dir', str(a.runtime_dir.resolve()),
               '--launcher', str(a.launcher.resolve())]
    if a.app:
        command += ['--app', str(a.app.resolve()), '--test-offscreen']
    else:
        command += ['--host-bin', str(a.host_bin.resolve())]
    installed = subprocess.run(command, capture_output=True)
    (a.output / 'install.log').write_bytes(installed.stdout + installed.stderr)
    if installed.returncode:
        print((installed.stdout + installed.stderr).decode('utf-8', errors='replace'))
        installed.check_returncode()
result = {'installed': True, 'corruptKitRejected': True, 'compiledDuringInstall': False,
          'archiveSHA256': hashlib.sha256(a.archive.read_bytes()).hexdigest(),
          'basecampLoadVerified': False}
(a.output / 'install-result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
