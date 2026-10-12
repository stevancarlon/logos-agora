#!/usr/bin/env python3
"""Stage missing Agora dependencies beside an unchanged extracted Basecamp host."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

p = argparse.ArgumentParser(description=__doc__)
for name in ('qt', 'host-bin', 'user-dir', 'runtime-dir', 'objdump'):
    p.add_argument('--' + name, type=Path, required=True)
a = p.parse_args()
if sys.platform != 'win32':
    p.error('Run on Windows with matching Qt MinGW builds')
root = Path(__file__).resolve().parents[1]
qt, host, runtime = a.qt.resolve(), a.host_bin.resolve(), a.runtime_dir.resolve()
backend = a.user_dir / 'plugins/logos_forum/forum_backend.dll'
if not backend.is_file() or not (host / 'LogosBasecamp.exe').is_file():
    p.error('Install the compiled Agora plugin and extract Basecamp first')
queue = [backend]
(runtime / 'bin').mkdir(parents=True, exist_ok=True)
renderer = root / 'build/qt6.9.2-media/qml/Agora/Media'
shutil.copytree(renderer, runtime / 'qml/Agora/Media', dirs_exist_ok=True)
queue.append(runtime / 'qml/Agora/Media/agoramedia.dll')
for category, pattern in [('multimedia', '*.dll'), ('sqldrivers', '*sqlite*.dll')]:
    sources = list((qt / 'plugins' / category).glob(pattern))
    if not sources:
        raise SystemExit(f'Missing Qt {category} plugins')
    for source in sources:
        dest = runtime / 'plugins' / category / source.name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)
        queue.append(dest)
lookup = {}
for directory in [qt / 'bin', a.objdump.parent, host]:
    for path in directory.glob('*.dll'):
        lookup[path.name.lower()] = path
system = Path(os.environ['SystemRoot']) / 'System32'
processed = set()
records = []
while queue:
    binary = queue.pop(0)
    if binary in processed:
        continue
    processed.add(binary)
    details = subprocess.check_output([str(a.objdump), '-p', str(binary)], text=True)
    imports = re.findall(r'DLL Name:\s*(\S+)', details)
    if not imports:
        raise SystemExit(f'No PE imports found in {binary}')
    records.append({'binary': str(binary), 'imports': imports})
    for name in imports:
        if name.lower().startswith(('api-ms-', 'ext-ms-')) or (system / name).is_file():
            continue
        source = lookup.get(name.lower())
        if source is None:
            raise SystemExit(f'Unresolved dependency {name} from {binary}')
        if source.parent == host:
            continue
        dest = runtime / 'bin' / name
        if not dest.exists():
            shutil.copy2(source, dest)
            queue.append(dest)
(runtime / 'dependencies.json').write_text(json.dumps(records, indent=2) + '\n')
print(f'Staged and checked {len(processed)} Agora libraries; Basecamp libraries unchanged')
