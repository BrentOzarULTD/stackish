#!/usr/bin/env python3
"""Render the existing red Stackish stack mark as desktop icons (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

assets = Path(__file__).resolve().parent / 'Stackish.Desktop' / 'Assets'
# Supersample the simple geometry to keep small taskbar and large Finder icons crisp.
scale = 4
image = Image.new('RGBA', (1024 * scale, 1024 * scale))
draw = ImageDraw.Draw(image)
def rounded(box, radius, color):
    draw.rounded_rectangle(tuple(v * scale for v in box), radius * scale, fill=color)
rounded((64, 64, 960, 960), 202, '#C8202F')
for left, top, right in [(236, 290, 788), (305, 466, 719), (374, 642, 650)]:
    rounded((left, top, right, top + 92), 24, 'white')
image = image.resize((1024, 1024), Image.Resampling.LANCZOS)
image.save(assets / 'Stackish.png')
image.save(assets / 'Stackish.ico', sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
image.save(assets / 'Stackish.icns')
