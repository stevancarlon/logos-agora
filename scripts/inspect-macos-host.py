#!/usr/bin/env python3
"""Record Mach-O dependencies from a Basecamp bundle before adapting the runtime."""
import argparse
import json
from pathlib import Path
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--app', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
app = a.app.resolve()
if not (app / 'Contents').is_dir():
    p.error('--app must identify a macOS application bundle')
records = []
for path in sorted((app / 'Contents').rglob('*')):
    if not path.is_file() or not any(name in path.name for name in ('QtCore', 'Qt6Core', 'LogosBasecamp', 'ui_host')):
        continue
    with path.open('rb') as stream:
        magic = stream.read(4)
    if magic not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        continue
    records.append({'path': str(path.relative_to(app)),
                    'architectures': subprocess.check_output(['lipo', '-info', str(path)], text=True).strip(),
                    'dependencies': subprocess.check_output(['otool', '-L', str(path)], text=True).splitlines()[1:]})
if not records:
    raise SystemExit('No host Mach-O binaries found; bundle layout needs investigation')
a.output.write_text(json.dumps({'bundle': app.name, 'binaries': records,
                                'agoraLoadVerified': False}, indent=2) + '\n')
print(a.output.read_text())
