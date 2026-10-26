import os
from pathlib import Path
import runpy
import sys
import tempfile
import types
import unittest
from unittest.mock import patch


class WindowsRuntimeUpgrade(unittest.TestCase):
    def test_existing_dependency_replaced_and_new_transitive_import_staged(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def file(relative, data=b'fixture'):
                p = root / relative
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(data)
                return p
            file('profile/plugins/logos_forum/forum_backend.dll')
            file('host/LogosBasecamp.exe')
            file('host/sqldrivers/qsqlite.dll')
            file('qt/plugins/multimedia/ffmpegmediaplugin.dll')
            file('qt/bin/codec.dll', b'new-codec')
            file('qt/bin/transitive.dll', b'new-transitive')
            file('renderer/agoramedia.dll')
            file('system/System32/kernel32.dll')
            file('runtime/bin/codec.dll', b'old-codec')
            inspected = []
            def imports(path):
                inspected.append(path.name)
                if path.name == 'ffmpegmediaplugin.dll': return ['codec.dll']
                if path.name == 'codec.dll': return ['transitive.dll']
                return ['kernel32.dll']
            command = ['stage-windows-runtime.py']
            for key, value in [('qt', 'qt'), ('host-bin', 'host'), ('user-dir', 'profile'),
                               ('runtime-dir', 'runtime'), ('renderer', 'renderer')]:
                command += ['--' + key, str(root / value)]
            script = Path(__file__).parents[1] / 'stage-windows-runtime.py'
            with patch.object(sys, 'platform', 'win32'), patch.object(sys, 'argv', command), \
                 patch.dict(os.environ, {'SystemRoot': str(root / 'system')}), \
                 patch.dict(sys.modules, {'pe_dependencies': types.SimpleNamespace(dll_imports=imports)}):
                runpy.run_path(str(script), run_name='__main__')
            self.assertEqual((root / 'runtime/bin/codec.dll').read_bytes(), b'new-codec')
            self.assertEqual((root / 'runtime/bin/transitive.dll').read_bytes(), b'new-transitive')
            self.assertIn('codec.dll', inspected)
            self.assertIn('transitive.dll', inspected)
            self.assertEqual((root / 'host/sqldrivers/qsqlite.dll').read_bytes(), b'fixture')


if __name__ == '__main__':
    unittest.main()
