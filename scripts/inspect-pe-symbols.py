#!/usr/bin/env python3
"""Diagnose named/ordinal PE imports against the staged Windows host DLLs."""
import argparse
import json
from pathlib import Path
import struct

class PE:
    def __init__(self, path):
        self.data = Path(path).read_bytes()
        pe = self.u32(60)
        if self.data[:2] != b'MZ' or self.data[pe:pe+4] != b'PE\0\0':
            raise ValueError(f'Invalid PE: {path}')
        optional = pe + 24
        magic = self.u16(optional)
        self.bits = {0x10b: 32, 0x20b: 64}[magic]
        directory = optional + (112 if self.bits == 64 else 96)
        self.export_rva = self.u32(directory)
        self.import_rva = self.u32(directory + 8)
        self.header_size = self.u32(optional + 60)
        table = optional + self.u16(pe + 20)
        self.sections = [struct.unpack_from('<IIII', self.data, table+i*40+8) for i in range(self.u16(pe+6))]
    def u16(self, at): return struct.unpack_from('<H', self.data, at)[0]
    def u32(self, at): return struct.unpack_from('<I', self.data, at)[0]
    def offset(self, rva):
        if rva < self.header_size: return rva
        for vs, va, size, start in self.sections:
            if 0 <= rva-va < size: return start+rva-va
        raise ValueError(f'Unmapped RVA {rva}')
    def string(self, rva):
        start = self.offset(rva)
        end = self.data.find(b'\0', start)
        if end < 0: raise ValueError('Unterminated PE string')
        return self.data[start:end].decode('ascii')
    def imports(self):
        if not self.import_rva: return []
        result = []
        for i in range(4096):
            fields = struct.unpack_from('<IIIII', self.data, self.offset(self.import_rva+i*20))
            if not any(fields): return result
            dll, thunk = self.string(fields[3]), fields[0] or fields[4]
            for j in range(65536):
                value = struct.unpack_from('<Q' if self.bits == 64 else '<I', self.data, self.offset(thunk+j*self.bits//8))[0]
                if not value: break
                symbol = value & 0xffff if value & (1 << (self.bits-1)) else self.string(value+2)
                result.append((dll, symbol))
            else: raise ValueError('Unterminated import thunk')
        raise ValueError('Unterminated import descriptors')
    def exports(self):
        if not self.export_rva: return set()
        at = self.offset(self.export_rva)
        base, functions, names, function_rva, name_rva, ordinals = struct.unpack_from('<IIIIII', self.data, at+16)
        if functions > 1000000 or names > 1000000: raise ValueError('Oversized export table')
        result = {base+i for i in range(functions) if self.u32(self.offset(function_rva+i*4))}
        result.update(self.string(self.u32(self.offset(name_rva+i*4))) for i in range(names))
        return result

def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('host-bin', 'runtime-dir', 'backend', 'output'):
        p.add_argument('--'+name, type=Path, required=True)
    a = p.parse_args()
    providers = {}
    for directory in [a.runtime_dir / 'bin', a.host_bin]:
        providers.update({x.name.lower(): x for x in directory.glob('*.dll')})
    exports, missing, checked = {}, [], 0
    for binary in [a.backend, *a.runtime_dir.rglob('*.dll')]:
        for dll, symbol in PE(binary).imports():
            provider = providers.get(dll.lower())
            if provider is None: continue  # System/API-set imports are outside this ABI check.
            if provider not in exports: exports[provider] = PE(provider).exports()
            checked += 1
            if symbol not in exports[provider]:
                missing.append({'binary': str(binary), 'provider': str(provider), 'symbol': symbol})
    report = {'checkedImports': checked, 'missingExports': missing, 'systemImportsChecked': False}
    a.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))

if __name__ == '__main__': main()
