"""Read a Windows PE file's DLL imports without requiring a compiler toolchain."""
from pathlib import Path
import struct


def dll_imports(path):
    data = Path(path).read_bytes()

    def unpack(fmt, offset):
        if offset < 0 or offset + struct.calcsize(fmt) > len(data):
            raise ValueError(f'Truncated PE file: {path}')
        return struct.unpack_from(fmt, data, offset)

    if data[:2] != b'MZ':
        raise ValueError(f'Not a PE file: {path}')
    pe, = unpack('<I', 60)
    if data[pe:pe + 4] != b'PE\0\0':
        raise ValueError(f'Invalid PE signature: {path}')
    sections, = unpack('<H', pe + 6)
    optional_size, = unpack('<H', pe + 20)
    optional = pe + 24
    magic, = unpack('<H', optional)
    directory_offset = {0x10b: 96, 0x20b: 112}.get(magic)
    if directory_offset is None or optional_size < directory_offset + 16 or not 1 <= sections <= 96:
        raise ValueError(f'Unsupported PE headers: {path}')
    count, = unpack('<I', optional + directory_offset - 4)
    if count < 2:
        return []
    import_rva, import_size = unpack('<II', optional + directory_offset + 8)
    if not import_rva:
        return []
    headers_size, = unpack('<I', optional + 60)
    table = optional + optional_size
    regions = [unpack('<IIII', table + i * 40 + 8) for i in range(sections)]

    def offset(rva):
        if rva < min(headers_size, len(data)):
            return rva
        for virtual_size, address, raw_size, raw_offset in regions:
            delta = rva - address
            if 0 <= delta < max(virtual_size, raw_size):
                if delta >= raw_size or raw_offset + delta >= len(data):
                    break
                return raw_offset + delta
        raise ValueError(f'Unmapped PE address in {path}')

    imports = []
    for i in range(min(import_size // 20, 4096)):
        descriptor = unpack('<IIIII', offset(import_rva + i * 20))
        if not any(descriptor):
            return imports
        start = offset(descriptor[3])
        end = data.find(b'\0', start, min(start + 261, len(data)))
        if end < 0:
            raise ValueError(f'Unterminated PE DLL name: {path}')
        name = data[start:end].decode('ascii')
        if not name or '/' in name or '\\' in name or ':' in name:
            raise ValueError(f'Invalid PE DLL name: {path}')
        imports.append(name)
    raise ValueError(f'Unterminated PE import table: {path}')
