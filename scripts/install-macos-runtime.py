#!/usr/bin/env python3
"""Stage Agora's missing Qt media dependencies beside an unchanged Basecamp app.

Development installer: run on macOS with matching Qt 6.9.2 and native builds.
It modifies only the specified Agora plugin/runtime and creates a launcher.
"""
import argparse
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys


def run(*args):
    return subprocess.check_output([str(x) for x in args], text=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('qt', 'app', 'user-dir', 'runtime-dir', 'launcher'):
        p.add_argument('--' + name, type=Path, required=True)
    a = p.parse_args()
    if sys.platform != 'darwin':
        p.error('This installer must run on macOS')
    qt, app, runtime = a.qt.resolve(), a.app.resolve(), a.runtime_dir.resolve()
    if run(qt / 'bin/qmake', '-query', 'QT_VERSION').strip() != '6.9.2':
        p.error('Qt 6.9.2 is required')
    contents = app / 'Contents'
    executable = contents / 'MacOS/LogosBasecamp.bin'
    backend = a.user_dir.resolve() / 'plugins/logos_forum/forum_backend.dylib'
    root = Path(__file__).resolve().parents[1]
    renderer = root / 'build/qt6.9.2-media/qml/Agora/Media'
    for required in (executable, backend, renderer / 'libagoramedia.dylib'):
        if not required.is_file():
            p.error(f'Missing native build or installation: {required}')
    host_dirs = [contents / 'Frameworks', contents / 'lib']
    runtime_dirs = [runtime / 'Frameworks', runtime / 'lib']
    for directory in runtime_dirs:
        directory.mkdir(parents=True, exist_ok=True)
    queue = []
    for category, pattern in [('multimedia', '*.dylib'), ('sqldrivers', '*sqlite*.dylib')]:
        sources = list((qt / 'plugins' / category).glob(pattern))
        if not sources:
            p.error(f'Missing Qt {category} plugins')
        for source in sources:
            destination = runtime / 'plugins' / category / source.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            queue.append((source, destination))
    shutil.copytree(renderer, runtime / 'qml/Agora/Media', dirs_exist_ok=True)
    queue += [(renderer / 'libagoramedia.dylib', runtime / 'qml/Agora/Media/libagoramedia.dylib'),
              (backend, backend)]
    processed = set()

    def provide(reference, origin):
        if reference.startswith(('/System/', '/usr/lib/')):
            return reference
        if '.framework/' in reference:
            relative = reference[reference.index('Qt'):]
        else:
            relative = Path(reference).name
        for directory in host_dirs + runtime_dirs:
            if (directory / relative).is_file():
                return '@rpath/' + relative
        source = qt / 'lib' / relative
        if not source.is_file() and reference.startswith('@loader_path/'):
            source = (origin.parent / reference[len('@loader_path/'):]).resolve()
        if not source.is_file() or not source.resolve().is_relative_to(qt):
            raise RuntimeError(f'Unresolved non-system dependency: {reference} from {origin}')
        if '.framework/' in relative:
            framework = relative.split('/')[0]
            shutil.copytree(qt / 'lib' / framework, runtime_dirs[0] / framework,
                            symlinks=True, dirs_exist_ok=True)
            destination = runtime_dirs[0] / relative
        else:
            destination = runtime_dirs[1] / relative
            shutil.copy2(source, destination)
        queue.append((source, destination))
        return '@rpath/' + relative

    while queue:
        origin, destination = queue.pop(0)
        if destination in processed:
            continue
        processed.add(destination)
        dependencies = [line.strip().split(' (compatibility')[0]
                        for line in run('otool', '-L', origin).splitlines()[1:]]
        identifiers = run('otool', '-D', origin).splitlines()[1:]
        for dependency in dependencies:
            if dependency in identifiers:
                continue
            replacement = provide(dependency, origin)
            if replacement != dependency:
                run('install_name_tool', '-change', dependency, replacement, destination)
        old_paths = re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset',
                               run('otool', '-l', destination))
        for old in old_paths:
            run('install_name_tool', '-delete_rpath', old, destination)
        for directory in host_dirs + runtime_dirs:
            run('install_name_tool', '-add_rpath', directory, destination)
        run('codesign', '--force', '--sign', '-', destination)
    launcher = a.launcher.resolve()
    launcher.parent.mkdir(parents=True, exist_ok=True)
    launcher.write_text('#!/bin/sh\nset -eu\n' +
        'export LOGOS_NO_SCHEME_REGISTER=1\n' +
        'export QML_IMPORT_PATH=' + shlex.quote(str(runtime / 'qml')) + '${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}\n' +
        'export QT_PLUGIN_PATH=' + shlex.quote(str(runtime / 'plugins')) + '${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}\n' +
        'exec ' + shlex.quote(str(executable)) + ' "$@"\n')
    launcher.chmod(0o755)
    print(f'Staged {len(processed)} native libraries; launcher: {launcher}')


if __name__ == '__main__':
    main()
