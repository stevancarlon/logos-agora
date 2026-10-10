#!/usr/bin/env python3
"""Install the compiled native Forum into a local Basecamp profile."""
import argparse, pathlib, shutil
root = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--user-dir', type=pathlib.Path, default=pathlib.Path.home()/'.local/share/Logos/LogosBasecamp')
args = p.parse_args()
source = root/'native/forum'
if not (source/'libforum_backend.so').is_file():
    raise SystemExit('Build native/backend first with Qt 6.9.2. See README.md.')
dest = args.user_dir/'plugins/logos_forum'
dest.mkdir(parents=True, exist_ok=True)
for folder in ('qml', 'assets'):
    shutil.copytree(source/folder, dest/folder, dirs_exist_ok=True)
for name in ('metadata.json', 'manifest.json', 'variant'):
    shutil.copy2(source/name, dest/name)
shutil.copy2(source/'libforum_backend.so', dest/'forum_backend.so')
print(f'Installed: {dest}\nRestart Basecamp, then open Forum. User data is preserved.')
