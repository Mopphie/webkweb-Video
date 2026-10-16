#!/usr/bin/env python3
"""Own procedural app icon: RGB squares, circle and triangle, no input assets/fonts.
Uses only Python's standard library. Do not use reference screenshots/logos.
"""
from pathlib import Path
import struct, zlib
size = 1024
pixels = bytearray()
for y in range(size):
    pixels.append(0)
    for x in range(size):
        inside = (x-512)**2 + (y-512)**2 < 330**2
        color = (25, 180, 170) if inside else (13, 25, 31)
        if 410 <= x <= 680 and abs(y-512) <= (680-x)*0.64:
            color = (250, 253, 253)
        pixels.extend(color)
def chunk(name, data):
    return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name+data) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels, 9)) + chunk(b'IEND', b'')
path = Path(__file__).resolve().parents[1] / 'App/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
path.write_bytes(png)
print('Generated own geometric RGB icon:', len(png), 'bytes')
