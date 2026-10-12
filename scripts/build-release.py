#!/usr/bin/env python3
"""Build a precompiled desktop release kit, containing no profiles or signing keys."""
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
    p.add_argument('--variant', choices=['linux-amd64', 'darwin-amd64', 'darwin-arm64', 'windows-amd64'], default='linux-amd64')
    p.add_argument('--backend', type=Path, help='Use a compiled backend from this target')
    p.add_argument('--renderer', type=Path, help='Use this target’s precompiled Agora/Media directory')
    a = p.parse_args()
    a.output.mkdir(parents=True, exist_ok=True)
    library = {'linux-amd64': 'libforum_backend.so', 'darwin-amd64': 'libforum_backend.dylib',
               'darwin-arm64': 'libforum_backend.dylib', 'windows-amd64': 'forum_backend.dll'}[a.variant]
    backend = a.backend or ROOT / 'native/forum' / library
    subprocess.run([sys.executable, str(ROOT / 'scripts/package-native.py'), '--lgx', a.lgx,
                    '--variant', a.variant, '--backend', str(backend)], check=True)
    version = json.loads((ROOT / 'native/forum/manifest.json').read_text())['version']
    name = f'agora-{version}-{a.variant}'
    with tempfile.TemporaryDirectory(prefix='agora-release-') as temporary:
        stage = Path(temporary) / name
        stage.mkdir()
        folders = ('native/forum/qml', 'native/forum/assets')
        for folder in folders:
            shutil.copytree(ROOT / folder, stage / folder)
        renderer_path = 'build/qt6.9.2-media/qml/Agora/Media'
        shutil.copytree(a.renderer or ROOT / renderer_path, stage / renderer_path)
        shutil.copy2(backend, stage / 'native/forum' / library)
        files = ['README.md', 'LICENSE-MIT', 'LICENSE-APACHE', 'docs/RELEASE.md', 'docs/STORAGE.md',
                 'native/forum/metadata.json',
                 'native/forum/manifest.json', 'native/forum/variant',
                 'scripts/install-basecamp.py', 'scripts/install-media-runtime.py', 'scripts/install-release.py',
                 'scripts/install-macos-runtime.py', 'scripts/stage-windows-runtime.py', 'scripts/pe_dependencies.py',
                 'docs/PLATFORMS.md', 'docs/DESKTOP-INSTALL.md',
                 f'artifacts/logos_forum-{version}-{a.variant}.lgx']
        for relative in files:
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        native_manifest_path = stage / 'native/forum/manifest.json'
        native_manifest = json.loads(native_manifest_path.read_text())
        native_manifest['main'] = {a.variant: library.removeprefix('lib')}
        native_manifest_path.write_text(json.dumps(native_manifest, indent=2) + '\n')
        (stage / 'native/forum/variant').write_text(a.variant)
        hashes = {str(path.relative_to(stage)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted(stage.rglob('*')) if path.is_file()}
        (stage / 'release.json').write_text(json.dumps(dict(version=version, platform=a.variant,
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
