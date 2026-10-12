#!/usr/bin/env python3
"""Verify and install a prebuilt Agora release, without compiling app code."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--verify-only', action='store_true')
    p.add_argument('--qt', type=Path, help='Matching Qt 6.9.2 gcc_64 directory with Multimedia')
    p.add_argument('--appimage', type=Path)
    p.add_argument('--user-dir', type=Path)
    p.add_argument('--runtime-dir', type=Path)
    p.add_argument('--launcher', type=Path)
    p.add_argument('--no-desktop', action='store_true')
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
