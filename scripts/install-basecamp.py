#!/usr/bin/env python3
"""Install the compiled native Forum into a local Basecamp profile."""
import argparse, pathlib, shutil, os, tempfile, platform, sys, json
root = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
if sys.platform == 'darwin':
    data_root = pathlib.Path.home()/'Library/Application Support'
    library, suffix, system = 'libforum_backend.dylib', 'dylib', 'darwin'
elif sys.platform == 'win32':
    data_root = pathlib.Path(os.environ['APPDATA'])
    library, suffix, system = 'forum_backend.dll', 'dll', 'windows'
else:
    data_root = pathlib.Path(os.environ.get('XDG_DATA_HOME', str(pathlib.Path.home()/'.local/share')))
    library, suffix, system = 'libforum_backend.so', 'so', 'linux'
architecture = {'x86_64': 'amd64', 'amd64': 'amd64', 'aarch64': 'arm64', 'arm64': 'arm64'}.get(platform.machine().lower())
if not architecture:
    raise SystemExit('Unsupported CPU architecture')
variant = system + '-' + architecture
p.add_argument('--user-dir', type=pathlib.Path, default=pathlib.Path(os.environ.get('LOGOS_USER_DIR', str(data_root/'Logos/LogosBasecamp'))))
args = p.parse_args()
source = root/'native/forum'
if not (source/library).is_file():
    raise SystemExit('Build native/backend first with Qt 6.9.2. See README.md.')
dest = args.user_dir/'plugins/logos_forum'
dest.mkdir(parents=True, exist_ok=True)
for folder in ('qml', 'assets'):
    shutil.copytree(source/folder, dest/folder, dirs_exist_ok=True)
for name in ('metadata.json',):
    shutil.copy2(source/name, dest/name)
manifest = json.loads((source/'manifest.json').read_text())
manifest['main'] = {variant: 'forum_backend.' + suffix}
(dest/'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(dest/'variant').write_text(variant)
# Replace the inode atomically: existing hosts may still map the old library.
fd, staged = tempfile.mkstemp(prefix='.forum_backend-', dir=dest)
os.close(fd)
try:
    shutil.copy2(source/library, staged)
    os.replace(staged, dest/('forum_backend.' + suffix))
finally:
    if os.path.exists(staged): os.unlink(staged)
print(f'Installed: {dest}\nRestart Basecamp, then open Forum. User data is preserved.')
