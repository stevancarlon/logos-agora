#!/usr/bin/env python3
"""Build a prebuilt Linux release kit, containing no profiles or signing keys."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--lgx', default='lgx')
    p.add_argument('--output', type=Path, default=ROOT / 'artifacts')
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, str(ROOT / 'scripts/package-native.py'), '--lgx', a.lgx], check=True)
    version = json.loads((ROOT / 'native/forum/manifest.json').read_text())['version']
    name = f'agora-{version}-linux-amd64'
    with tempfile.TemporaryDirectory(prefix='agora-release-') as temporary:
        stage = Path(temporary) / name
        stage.mkdir()
        folders = ('native/forum/qml', 'native/forum/assets', 'build/qt6.9.2-media/qml/Agora/Media')
        for folder in folders:
            shutil.copytree(ROOT / folder, stage / folder)
        files = ['README.md', 'LICENSE-MIT', 'LICENSE-APACHE', 'docs/RELEASE.md', 'docs/STORAGE.md',
                 'native/forum/libforum_backend.so', 'native/forum/metadata.json',
                 'native/forum/manifest.json', 'native/forum/variant',
                 'scripts/install-basecamp.py', 'scripts/install-media-runtime.py', 'scripts/install-release.py',
                 f'artifacts/logos_forum-{version}-linux-amd64.lgx']
        for relative in files:
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        hashes = {str(path.relative_to(stage)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted(stage.rglob('*')) if path.is_file()}
        (stage / 'release.json').write_text(json.dumps(dict(version=version, platform='linux-amd64',
            qt='6.9.2', basecamp='0.3.2', signed=False, sha256=hashes), indent=2) + '\n')
        subprocess.run([sys.executable, str(stage / 'scripts/install-release.py'), '--verify-only'], check=True)
        output = a.output / (name + '.tar.gz')
        with tarfile.open(output, 'w:gz') as archive:
            archive.add(stage, arcname=name)
        output.with_suffix(output.suffix + '.sha256').write_text(
            hashlib.sha256(output.read_bytes()).hexdigest() + '  ' + output.name + '\n')
        print(output)


if __name__ == '__main__':
    main()
