import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('receipts', Path(__file__).parents[1] / 'check-peer-receipts.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


class ReceiptChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'forum.sqlite'
        self.db = sqlite3.connect(self.path)
        self.addCleanup(self.db.close)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('CREATE TABLE posts(id TEXT, thread TEXT, wire TEXT, status TEXT, received INTEGER)')
        self.db.execute('CREATE TABLE identities(secret TEXT)')
        self.db.execute("INSERT INTO identities VALUES ('private-key-never-export')")
        self.db.execute('INSERT INTO posts VALUES (?, ?, ?, ?, ?)', ('a'*64, '', 'private-message-text', 'received', 123))
        self.db.commit()

    def export(self, label='mac'):
        return r.snapshot(self.path, ['a'*64], label, 'live')

    def test_live_wal_read_and_no_sensitive_export(self):
        before = self.db.execute('SELECT * FROM posts').fetchall()
        report = self.export()
        self.assertEqual(report['messages'][0]['receivedAt'], 123)
        encoded = json.dumps(report)
        for secret in ('private-key-never-export', 'private-message-text', str(self.path)):
            self.assertNotIn(secret, encoded)
        self.assertEqual(before, self.db.execute('SELECT * FROM posts').fetchall())

    def test_missing_file_is_not_created(self):
        missing = self.path.with_name('missing.sqlite')
        with self.assertRaises(FileNotFoundError):
            r.snapshot(missing, ['a'*64], 'mac', 'live')
        self.assertFalse(missing.exists())

    def test_missing_id_rejected(self):
        with self.assertRaises(ValueError):
            r.snapshot(self.path, ['b'*64], 'mac', 'live')

    def test_match_does_not_claim_cross_machine_proof(self):
        result = r.compare(self.export('linux'), self.export('mac'))
        self.assertTrue(result['passed'])
        self.assertFalse(result['crossMachineVerified'])

    def test_different_wire_rejected(self):
        a, b = self.export('linux'), self.export('mac')
        b['messages'][0]['wireSha256'] = '0'*64
        self.assertFalse(r.compare(a, b)['passed'])

    def test_sent_alone_is_not_receipt(self):
        a, b = self.export('linux'), self.export('mac')
        a['messages'][0]['status'] = b['messages'][0]['status'] = 'sent'
        self.assertFalse(r.compare(a, b)['passed'])

    def test_different_phases_and_duplicate_ids_rejected(self):
        a, b = self.export('linux'), self.export('mac')
        b['phase'] = 'restart'
        with self.assertRaises(ValueError):
            r.compare(a, b)
        b['phase'] = 'live'
        b['messages'] *= 2
        with self.assertRaises(ValueError):
            r.compare(a, b)


if __name__ == '__main__':
    unittest.main()
