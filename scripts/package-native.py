#!/usr/bin/env python3
"""Create and validate an unsigned local LGX with the official lgx CLI."""
import argparse, io, json, pathlib, shutil, subprocess, tarfile, tempfile, platform, struct
root = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--lgx', default='lgx')
host_arch = {'x86_64': 'amd64', 'amd64': 'amd64', 'arm64': 'arm64', 'aarch64': 'arm64'}.get(platform.machine().lower(), '')
host_variant = platform.system().lower() + '-' + host_arch
p.add_argument('--variant', choices=['linux-amd64', 'darwin-amd64', 'darwin-arm64', 'windows-amd64'], default=host_variant)
p.add_argument('--backend', type=pathlib.Path, help='Compiled native backend for the selected variant')
args = p.parse_args()
suffix = {'linux': 'so', 'darwin': 'dylib', 'windows': 'dll'}[args.variant.split('-')[0]]
source_name = ('lib' if suffix != 'dll' else '') + 'forum_backend.' + suffix
backend = args.backend or root/'native/forum'/source_name
binary = backend.read_bytes()
valid = False
if args.variant == 'linux-amd64':
    valid = len(binary) >= 20 and binary[:6] == b'\x7fELF\x02\x01' and struct.unpack_from('<H', binary, 18)[0] == 62
elif args.variant == 'windows-amd64':
    if len(binary) >= 64 and binary[:2] == b'MZ':
        offset = struct.unpack_from('<I', binary, 60)[0]
        valid = offset + 6 <= len(binary) and binary[offset:offset+4] == b'PE\0\0' and struct.unpack_from('<H', binary, offset+4)[0] == 0x8664
elif args.variant.startswith('darwin-'):
    # The build driver deliberately emits one native architecture per job.
    cpu = 0x01000007 if args.variant.endswith('amd64') else 0x0100000c
    valid = len(binary) >= 8 and binary[:4] == b'\xcf\xfa\xed\xfe' and struct.unpack_from('<I', binary, 4)[0] == cpu
if not valid:
    raise SystemExit(f'Backend binary format/architecture does not match {args.variant}')
main_file = 'forum_backend.' + suffix
manifest = json.loads((root/'native/forum/module.json').read_text())
output = root/'artifacts'/f"logos_forum-{manifest['version']}-{args.variant}.lgx"
output.parent.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    stage = pathlib.Path(tmp)
    shutil.copytree(root/'native/forum/qml', stage/'qml')
    shutil.copy2(root/'native/forum/metadata.json', stage/'metadata.json')
    (stage/'variant').write_text(args.variant)
    shutil.copy2(backend, stage/main_file)
    manifest['main'] = {}
    data = json.dumps(manifest).encode()
    with tarfile.open(output, 'w:gz', format=tarfile.USTAR_FORMAT) as archive:
        entry = tarfile.TarInfo('manifest.json')
        entry.size = len(data)
        archive.addfile(entry, io.BytesIO(data))
        archive.add(root/'native/forum/assets/icon.png', arcname='assets/icon.png')
        for license in ('LICENSE-MIT', 'LICENSE-APACHE'):
            archive.add(root/license, arcname='licenses/'+license)
    subprocess.run([args.lgx, 'add', str(output), '--variant', args.variant,
                    '--files', str(stage), '--main', main_file, '--view',
                    'qml/Main.qml', '--icon', str(root/'native/forum/assets/icon.png'), '-y'], check=True)
    subprocess.run([args.lgx, 'verify', str(output)], check=True)
print(output)
