"""Generate a simple opaque app icon, without external dependencies."""
import json
import math
from pathlib import Path
import struct
import zlib

size = 1024
pixels = bytearray()
for y in range(size):
    pixels.append(0)  # PNG filter type
    for x in range(size):
        t = (x + y) / (2 * size)
        color = (int(14 + 12 * t), int(100 + 38 * t), int(105 + 24 * t))
        distance = math.hypot(x - 512, y - 512)
        if 290 < distance < 325:
            color = (210, 244, 230)
        # A calm central wave made of three rounded bars.
        for center, halfheight in ((390, 90), (512, 165), (634, 125)):
            dx, dy = abs(x - center), max(0, abs(y - 512) - halfheight + 24)
            if dx * dx + dy * dy < 24 * 24:
                color = (240, 255, 248)
        pixels.extend(color)

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)

png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(bytes(pixels), 9)) + chunk(b'IEND', b'')
root = Path(__file__).resolve().parent.parent / 'App' / 'Assets.xcassets'
icon = root / 'AppIcon.appiconset'
icon.mkdir(parents=True, exist_ok=True)
(icon / 'AppIcon.png').write_bytes(png)
(root / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
(icon / 'Contents.json').write_text(json.dumps({
    'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
    'info': {'author': 'xcode', 'version': 1}
}, indent=2))
print('Generated AppIcon.png')
