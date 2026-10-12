#!/usr/bin/env python3
"""Install the pinned official Delivery package into a marked disposable profile."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import tarfile
import tempfile
import urllib.request

URL = 'https://github.com/logos-co/logos-modules-release/releases/download/delivery_module-v0.3.2/delivery_module-0.3.2.lgx'
SHA256 = '9b856418fcf816961f1118f34b395bb6a399e5523166be51f4eca6a7aaf76867'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--profile', type=Path, required=True)
p.add_argument('--archive', type=Path, help='Reuse an already downloaded official package')
a = p.parse_args()
if not (a.profile / '.agora-disposable-profile').is_file():
    p.error('Refusing to modify an unmarked profile')
variant = {('Windows', 'amd64'): 'windows-x86_64', ('Darwin', 'arm64'): 'darwin-arm64',
           ('Linux', 'x86_64'): 'linux-amd64'}.get((platform.system(), platform.machine().lower()))
if variant is None:
    p.error('The pinned upstream package has no variant for this test host')
with tempfile.TemporaryDirectory(prefix='agora-delivery-') as temporary:
    work = Path(temporary)
    archive = a.archive or work / 'delivery.lgx'
    if not a.archive:
        with urllib.request.urlopen(URL, timeout=60) as response, archive.open('wb') as stream:
            shutil.copyfileobj(response, stream)
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != SHA256:
        raise SystemExit('Official Delivery package checksum mismatch')
    with tarfile.open(archive) as bundle:
        members = [m for m in bundle.getmembers() if m.name == 'manifest.json' or m.name.startswith('variants/' + variant + '/')]
        bundle.extractall(work / 'extracted', members=members, filter='data')
    manifest = json.loads((work / 'extracted/manifest.json').read_text())
    if manifest['name'] != 'delivery_module' or manifest['version'] != '0.3.2':
        raise SystemExit('Unexpected Delivery package identity')
    source = work / 'extracted/variants' / variant
    if not (source / manifest['main'][variant]).is_file():
        raise SystemExit('Missing native Delivery entry point')
    destination = a.profile / 'modules/delivery_module'
    if destination.exists():
        raise SystemExit('Refusing to overwrite an installed Delivery module')
    shutil.copytree(source, destination)
    shutil.copy2(work / 'extracted/manifest.json', destination / 'manifest.json')
    (destination / 'variant').write_text(variant)
    print(f'Installed pinned official Delivery 0.3.2 ({variant}), sha256={digest}')
