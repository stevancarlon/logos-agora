#!/usr/bin/env python3
"""Create and validate an unsigned local LGX with the official lgx CLI."""
import argparse, io, json, pathlib, shutil, subprocess, tarfile, tempfile
root = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--lgx', default='lgx')
args = p.parse_args()
manifest = json.loads((root/'native/forum/manifest.json').read_text())
output = root/'artifacts'/f"logos_forum-{manifest['version']}-linux-amd64.lgx"
output.parent.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    stage = pathlib.Path(tmp)
    shutil.copytree(root/'native/forum/qml', stage/'qml')
    shutil.copy2(root/'native/forum/metadata.json', stage/'metadata.json')
    shutil.copy2(root/'native/forum/variant', stage/'variant')
    shutil.copy2(root/'native/forum/libforum_backend.so', stage/'forum_backend.so')
    manifest['main'] = {}
    data = json.dumps(manifest).encode()
    with tarfile.open(output, 'w:gz', format=tarfile.USTAR_FORMAT) as archive:
        entry = tarfile.TarInfo('manifest.json')
        entry.size = len(data)
        archive.addfile(entry, io.BytesIO(data))
        archive.add(root/'native/forum/assets/icon.png', arcname='assets/icon.png')
        for license in ('LICENSE-MIT', 'LICENSE-APACHE'):
            archive.add(root/license, arcname='licenses/'+license)
    subprocess.run([args.lgx, 'add', str(output), '--variant', 'linux-amd64',
                    '--files', str(stage), '--main', 'forum_backend.so', '--view',
                    'qml/Main.qml', '--icon', str(root/'native/forum/assets/icon.png'), '-y'], check=True)
    subprocess.run([args.lgx, 'verify', str(output)], check=True)
print(output)
