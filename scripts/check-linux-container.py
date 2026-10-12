#!/usr/bin/env python3
"""Check a prebuilt kit in fresh Ubuntu userspace, without host user data."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--qt', type=Path, required=True)
    parser.add_argument('--basecamp', type=Path, required=True)
    parser.add_argument('--modules', type=Path, required=True)
    parser.add_argument('--build-network', choices=('default', 'host'), default='default',
                        help='Networking for package downloads only; runtime stays offline')
    parser.add_argument('--output', type=Path, default=ROOT / 'artifacts/ubuntu-release-check')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    image = 'agora-runtime-check:ubuntu24'
    subprocess.run(['docker', 'build', '--network', args.build_network, '-t', image, '-f',
                    str(ROOT / 'scripts/containers/ubuntu-runtime.Dockerfile'),
                    str(ROOT / 'scripts/containers')], check=True)
    command = ['docker', 'run', '--rm', '--network', 'none', '--memory', '2g', '--cpus', '2']
    mounts = [(args.archive, '/input/release.tar.gz'), (args.qt, '/input/qt'),
              (args.basecamp, '/input/Basecamp.AppImage'), (args.modules, '/input/modules'),
              (ROOT / 'scripts/check-release.py', '/input/check-release.py')]
    for source, destination in mounts:
        command += ['--mount', f'type=bind,src={source.resolve()},dst={destination},readonly']
    command += ['--mount', f'type=bind,src={args.output.resolve()},dst=/output',
                image, 'python3', '/input/check-release.py',
                '--archive', '/input/release.tar.gz', '--qt', '/input/qt',
                '--basecamp', '/input/Basecamp.AppImage', '--modules', '/input/modules',
                '--output', '/output']
    result_path = args.output / 'result.json'
    result_path.unlink(missing_ok=True)
    outcome = subprocess.run(command)
    if result_path.exists():
        result = json.loads(result_path.read_text())
        result.update(container='Ubuntu 24.04', hostKernelShared=True,
                      fullDesktopVerified=False, runtimeNetwork='disabled',
                      archiveSha256=hashlib.sha256(args.archive.read_bytes()).hexdigest())
        result_path.write_text(json.dumps(result, indent=2) + '\n')
    return outcome.returncode


if __name__ == '__main__':
    raise SystemExit(main())
