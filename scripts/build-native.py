#!/usr/bin/env python3
"""Build native Agora and run its tests using the host's matching Qt toolchain."""
import os
import platform
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    qmake = os.environ.get('QMAKE', 'qmake6')
    version = subprocess.check_output([qmake, '-query', 'QT_VERSION'], text=True).strip()
    if version != '6.9.2' and os.environ.get('ALLOW_OTHER_QT') != '1':
        raise SystemExit('Basecamp 0.3.2 requires Qt 6.9.2. Set QMAKE to its qmake.')
    windows = sys.platform == 'win32'
    make = os.environ.get('MAKE') or ('nmake' if windows else 'make')
    jobs = os.environ.get('JOBS', '4')
    projects = {'media': 'media-renderer/media.pro', 'backend': 'backend/forum.pro',
                'preview': 'preview/preview.pro', 'tests': 'tests/tests.pro',
                'ui-tests': 'tests/ui.pro', 'storage-probe': 'tests/storage.pro'}
    for target, project in projects.items():
        directory = ROOT / f'build/qt{version}-{target}'
        directory.mkdir(parents=True, exist_ok=True)
        configuration = ['CONFIG+=release', 'CONFIG-=debug_and_release']
        if sys.platform == 'darwin':
            configuration += [f'QMAKE_APPLE_DEVICE_ARCHS={platform.machine()}']
        subprocess.run([qmake, str(ROOT / 'native' / project), *configuration],
                       cwd=directory, check=True)
        options = ['/NOLOGO'] if Path(make).stem.lower() == 'nmake' else [f'-j{jobs}']
        subprocess.run([make, *options], cwd=directory, check=True)
    env = dict(os.environ)
    qt_bin = subprocess.check_output([qmake, '-query', 'QT_INSTALL_BINS'], text=True).strip()
    env['PATH'] = qt_bin + os.pathsep + env.get('PATH', '')
    if windows and env.get('OPENSSL_ROOT_DIR'):
        env['PATH'] = str(Path(env['OPENSSL_ROOT_DIR']) / 'bin') + os.pathsep + env['PATH']
    env['QML_IMPORT_PATH'] = str(ROOT / f'build/qt{version}-media/qml') + (
        os.pathsep + env['QML_IMPORT_PATH'] if env.get('QML_IMPORT_PATH') else '')
    env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')

    def executable(target, name):
        directory = ROOT / f'build/qt{version}-{target}'
        filename = name + ('.exe' if windows else '')
        for candidate in (directory / filename, directory / 'release' / filename):
            if candidate.is_file():
                return str(candidate)
        raise FileNotFoundError(f'Build did not produce {name} in {directory}')

    subprocess.run([executable('tests', 'backend_tests'), '-nocrashhandler', '-o', '-,txt'],
                   cwd=ROOT, env=env, check=True)
    subprocess.run([executable('ui-tests', 'forum-ui-tests'), '-input',
                    'native/tests/qml', '-nocrashhandler', '-o', '-,txt'], cwd=ROOT, env=env, check=True)


if __name__ == '__main__':
    main()
