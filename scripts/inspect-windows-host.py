#!/usr/bin/env python3
"""Inspect extracted Basecamp PE imports without executing the installer."""
import argparse
import json
from pathlib import Path
import re
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--directory', type=Path, required=True)
p.add_argument('--objdump', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
records = []
for path in sorted(a.directory.rglob('*')):
    if not path.is_file() or path.name.lower() not in {
        'logosbasecamp.exe', 'logos_host.exe', 'logos_ui_host.exe',
        'qt6core.dll', 'libstdc++-6.dll', 'libgcc_s_seh-1.dll', 'libcrypto-3-x64.dll'}:
        continue
    details = subprocess.check_output([str(a.objdump), '-p', str(path)], text=True)
    records.append({'path': str(path.relative_to(a.directory)),
                    'imports': re.findall(r'DLL Name:\s*(\S+)', details)})
if not any(Path(r['path']).name.lower() == 'logosbasecamp.exe' for r in records):
    raise SystemExit('No Basecamp executable found in extracted installer')
a.output.write_text(json.dumps({'binaries': records, 'agoraLoadVerified': False}, indent=2) + '\n')
print(a.output.read_text())
