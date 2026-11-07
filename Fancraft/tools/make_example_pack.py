#!/usr/bin/env python3
"""Write build/example_pack.zip: a tiny Fancraft texture pack for testing imports.

Uses only the standard library (PNG encoded by hand with zlib/struct).
"""
from pathlib import Path
import json
import struct
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]


def png(size, pixel):
    """RGBA PNG where pixel(x, y) -> (r, g, b, a)."""
    raw = b''.join(b'\x00' + b''.join(bytes(pixel(x, y)) for x in range(size)) for y in range(size))
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def main():
    size = 32
    files = {
        'pack.json': json.dumps({'name': 'Example Checker', 'description': 'Test pack: checker stone, pink planks.',
                                 'author': 'Fancraft', 'resolution': size, 'pixel_art': True}, indent=2).encode(),
        'textures/stone.png': png(size, lambda x, y: (110, 110, 120, 255) if (x // 8 + y // 8) % 2 else (160, 160, 170, 255)),
        # height map: raised squares, sunken grid lines
        'textures/stone_h.png': png(size, lambda x, y: (40, 40, 40, 255) if x % 8 == 0 or y % 8 == 0 else (220, 220, 220, 255)),
        'textures/planks.png': png(size, lambda x, y: (230, 120, 170, 255) if y % 8 else (120, 50, 80, 255)),
    }
    out = ROOT / 'build' / 'example_pack.zip'
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            z.writestr('example_checker/' + name, data)
    print(out)


if __name__ == '__main__':
    main()
