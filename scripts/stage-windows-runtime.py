#!/usr/bin/env python3
"""Stage missing Agora dependencies beside an unchanged extracted Basecamp host."""
import argparse
import json
import os
from pathlib import Path
import shutil
from pe_dependencies import dll_imports
import sys

p = argparse.ArgumentParser(description=__doc__)
for name in ('qt', 'host-bin', 'user-dir', 'runtime-dir'):
    p.add_argument('--' + name, type=Path, required=True)
p.add_argument('--renderer', type=Path, help='Directory containing the matching compiled Agora.Media module')
p.add_argument('--toolchain', type=Path, help='Optional MinGW runtime DLL directory')
p.add_argument('--launcher', type=Path, help='Write a Windows launch script')
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
renderer = a.renderer or root / 'build/qt6.9.2-media/qml/Agora/Media'
shutil.copytree(renderer, runtime / 'qml/Agora/Media', dirs_exist_ok=True)
queue.append(runtime / 'qml/Agora/Media/agoramedia.dll')
for category, pattern in [('multimedia', '*.dll'), ('sqldrivers', '*sqlite*.dll')]:
    # Prefer Basecamp's own SQLite plugin. Multimedia is the matching companion.
    bases = ([host / 'sqldrivers', host / 'plugins/sqldrivers',
              host.parent / 'plugins/sqldrivers', host.parent / 'lib/qt-6/plugins/sqldrivers']
             if category == 'sqldrivers' else [])
    bases += [qt / 'plugins' / category, qt / 'lib/qt-6/plugins' / category]
    sources = next((list(base.glob(pattern)) for base in bases if list(base.glob(pattern))), [])
    if not sources:
        raise SystemExit(f'Missing Qt {category} plugins')
    for source in sources:
        dest = runtime / 'plugins' / category / source.name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)
        queue.append(dest)
lookup = {}
toolchain = a.toolchain or qt.parents[1] / 'Tools/mingw1310_64/bin'
for directory in [qt / 'bin', toolchain, host]:
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
    imports = dll_imports(binary)
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

if a.launcher:
    def batch_path(path):
        return str(path.resolve()).replace('%', '%%')
    lines = ['@echo off', 'setlocal DisableDelayedExpansion', 'chcp 65001 >nul',
             'set "LOGOS_NO_SCHEME_REGISTER=1"',
             'set "LOGOS_USER_DIR=' + batch_path(a.user_dir) + '"',
             'set "PATH=' + batch_path(host) + ';' + batch_path(runtime / 'bin') + ';%PATH%"',
             'set "QT_PLUGIN_PATH=' + batch_path(runtime / 'plugins') + '"',
             'set "QML_IMPORT_PATH=' + batch_path(runtime / 'qml') + '"',
             '"' + batch_path(host / 'LogosBasecamp.exe') + '" %*',
             'exit /b %ERRORLEVEL%']
    a.launcher.parent.mkdir(parents=True, exist_ok=True)
    a.launcher.write_bytes(('\r\n'.join(lines) + '\r\n').encode('utf-8'))
    print(f'Launcher: {a.launcher}')
