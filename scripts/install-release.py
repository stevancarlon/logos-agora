#!/usr/bin/env python3
"""Verify and install a prebuilt Agora release, without compiling app code."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--verify-only', action='store_true')
    p.add_argument('--qt', type=Path, help='Matching Qt 6.9.2 directory with Multimedia')
    p.add_argument('--appimage', type=Path)
    p.add_argument('--app', type=Path, help='macOS Basecamp application bundle')
    p.add_argument('--host-bin', type=Path, help='Windows Basecamp bin directory')
    p.add_argument('--user-dir', type=Path)
    p.add_argument('--runtime-dir', type=Path)
    p.add_argument('--launcher', type=Path)
    p.add_argument('--no-desktop', action='store_true')
    p.add_argument('--test-offscreen', action='store_true', help='Stage the Mac display plugin used by CI')
    a = p.parse_args()
    manifest = json.loads((ROOT / 'release.json').read_text())
    for relative, digest in manifest['sha256'].items():
        path = (ROOT / relative).resolve()
        if not path.is_relative_to(ROOT) or not path.is_file():
            raise SystemExit(f'Missing or unsafe release file: {relative}')
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit(f'Release checksum mismatch: {relative}')
    print(f"Verified Agora {manifest['version']} ({manifest['platform']}); checksums are not a signature.")
    if a.verify_only:
        return
    arch = {'x86_64': 'amd64', 'amd64': 'amd64', 'arm64': 'arm64', 'aarch64': 'arm64'}.get(platform.machine().lower())
    host = platform.system().lower() + '-' + str(arch)
    if manifest['platform'] != host:
        p.error(f"This kit targets {manifest['platform']}, but this computer is {host}")
    if a.qt:
        qmake = a.qt / 'bin' / ('qmake.exe' if host.startswith('windows-') else 'qmake')
        version = subprocess.check_output([str(qmake), '-query', 'QT_VERSION'], text=True).strip()
        if version != manifest['qt']:
            p.error(f"This kit requires Qt {manifest['qt']}, found {version}")
    if host.startswith(('darwin-', 'windows-')):
        if not a.qt or (host.startswith('darwin-') and not a.app) or (host.startswith('windows-') and not a.host_bin):
            p.error('Provide --qt and --app (macOS) or --host-bin (Windows)')
        if host.startswith('darwin-'):
            data = Path.home() / 'Library/Application Support'
            user_dir = a.user_dir or Path(os.environ.get('LOGOS_USER_DIR', str(data / 'Logos/LogosBasecamp')))
            runtime = a.runtime_dir or data / 'Logos/Agora/qt-media-6.9.2'
            launcher = a.launcher or Path.home() / 'Applications/Agora.command'
            command = [sys.executable, str(ROOT / 'scripts/install-macos-runtime.py'), '--app', str(a.app.resolve())]
        else:
            user_dir = a.user_dir or Path(os.environ.get('LOGOS_USER_DIR', str(Path(os.environ['APPDATA']) / 'Logos/LogosBasecamp')))
            data = Path(os.environ['LOCALAPPDATA'])
            runtime = a.runtime_dir or data / 'Logos/Agora/qt-media-6.9.2'
            launcher = a.launcher or data / 'Programs/Agora/Launch-Agora.cmd'
            command = [sys.executable, str(ROOT / 'scripts/stage-windows-runtime.py'), '--host-bin', str(a.host_bin.resolve())]
        subprocess.run([sys.executable, str(ROOT / 'scripts/install-basecamp.py'), '--user-dir', str(user_dir.resolve())], check=True)
        command += ['--qt', str(a.qt.resolve()), '--user-dir', str(user_dir.resolve()),
                    '--runtime-dir', str(runtime.resolve()), '--launcher', str(launcher.resolve())]
        if a.test_offscreen and host.startswith('darwin-'):
            command.append('--test-offscreen')
        subprocess.run(command, check=True)
        return
    if not a.qt or not a.appimage:
        p.error('--qt and --appimage are required for installation; see docs/RELEASE.md')
    media = [sys.executable, str(ROOT / 'scripts/install-media-runtime.py'),
             '--qt', str(a.qt.resolve()), '--appimage', str(a.appimage.resolve())]
    for name in ('runtime_dir', 'launcher'):
        if getattr(a, name):
            media.extend(['--' + name.replace('_', '-'), str(getattr(a, name).resolve())])
    if a.no_desktop:
        media.append('--no-desktop')
    subprocess.run(media, check=True)
    install = [sys.executable, str(ROOT / 'scripts/install-basecamp.py')]
    if a.user_dir:
        install.extend(['--user-dir', str(a.user_dir.resolve())])
    subprocess.run(install, check=True)


if __name__ == '__main__':
    main()
