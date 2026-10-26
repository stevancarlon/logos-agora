#!/usr/bin/env python3
"""Export selected read-only receipts, or compare receipts from two installations.

Matching receipts demonstrate database agreement, not independent proof of network
transport, signatures, separate hardware, Store recovery, or organic adoption.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import re
import sqlite3


def snapshot(database, ids, label, phase):
    if not ids or len(set(ids)) != len(ids) or any(not re.fullmatch(r'[0-9a-f]{64}', x) for x in ids):
        raise ValueError('Provide distinct, complete lowercase message IDs (64 hex characters)')
    database = database.resolve(strict=True)
    # mode=ro observes the live WAL; immutable=1 would miss uncheckpointed posts.
    with sqlite3.connect(database.as_uri() + '?mode=ro', uri=True) as db:
        db.execute('PRAGMA query_only=ON')
        db.execute('BEGIN')
        records = []
        for ident in sorted(ids):
            rows = db.execute('SELECT id,thread,wire,status,received FROM posts WHERE id=?', (ident,)).fetchall()
            if len(rows) != 1:
                raise ValueError('Expected exactly one stored message: ' + ident)
            row = rows[0]
            records.append(dict(id=row[0], thread=row[1], wireSha256=hashlib.sha256(row[2].encode('utf-8')).hexdigest(), status=row[3], receivedAt=row[4]))
    return dict(schema=1, installation=label, phase=phase, capturedAt=datetime.now(timezone.utc).isoformat(),
                os=platform.system(), architecture=platform.machine(), messages=records,
                scope='Selected database receipts; no message text, identity keys, or local paths exported')


def compare(left, right):
    if left.get('schema') != 1 or right.get('schema') != 1:
        raise ValueError('Unsupported receipt schema')
    if not left.get('installation') or not right.get('installation') or left['installation'] == right['installation']:
        raise ValueError('Use distinct installation labels; labels alone do not prove separate hardware')
    if not left.get('phase') or left['phase'] != right.get('phase'):
        raise ValueError('Compare receipts captured for the same test phase')
    def index(receipt):
        messages = receipt.get('messages', [])
        result = {m['id']: m for m in messages}
        if not messages or len(result) != len(messages):
            raise ValueError('Empty or duplicate message receipts')
        for m in messages:
            if not re.fullmatch(r'[0-9a-f]{64}', m['id']) or not re.fullmatch(r'[0-9a-f]{64}', m['wireSha256']):
                raise ValueError('Invalid message ID or envelope hash')
        return result
    a, b = index(left), index(right)
    problems = []
    for ident in sorted(a.keys() | b.keys()):
        if ident not in a or ident not in b:
            problems.append(dict(id=ident, reason='missing from one installation'))
        elif any(a[ident][k] != b[ident][k] for k in ('wireSha256', 'thread')):
            problems.append(dict(id=ident, reason='envelope or parent differs'))
        elif 'received' not in (a[ident]['status'], b[ident]['status']):
            problems.append(dict(id=ident, reason='neither installation records incoming receipt'))
    return dict(passed=not problems, phase=left['phase'], comparedMessages=len(a.keys() | b.keys()), problems=problems,
                crossMachineVerified=False, scope='Database agreement only; retain separate machine and transport evidence')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    export = sub.add_parser('snapshot')
    export.add_argument('--database', type=Path, required=True)
    export.add_argument('--id', action='append', required=True, dest='ids')
    export.add_argument('--installation', required=True, help='Test label, e.g. linux-a or intel-mac-b')
    export.add_argument('--phase', required=True, help='Agreed phase, e.g. live or offline-recovery')
    export.add_argument('--output', type=Path, required=True)
    check = sub.add_parser('compare')
    check.add_argument('left', type=Path)
    check.add_argument('right', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'snapshot':
            report = snapshot(args.database, args.ids, args.installation, args.phase)
            # Never overwrite an existing file, including the source database.
            with args.output.open('x', encoding='utf-8') as out:
                json.dump(report, out, indent=2)
                out.write('\n')
            return 0
        report = compare(json.loads(args.left.read_text()), json.loads(args.right.read_text()))
        print(json.dumps(report, indent=2))
        return 0 if report['passed'] else 1
    except (OSError, ValueError, KeyError, TypeError, sqlite3.Error) as error:
        parser.exit(2, str(error) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
