#!/usr/bin/env python3
"""Generate padded splash_logo.png for flutter_native_splash.

Android 12+ clips the splash icon to a circle (~768px diameter on a 1152px
canvas). Logo artwork must fit inside that circle — not fill the whole PNG.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'assets' / 'bgless_logo.png'
OUT = ROOT / 'assets' / 'splash_logo.png'
CANVAS = 1152
# Max logo edge length inside the 768px Android 12 safe circle.
LOGO_MAX = 680


def main() -> None:
    src = Image.open(SRC).convert('RGBA')
    w, h = src.size
    scale = min(LOGO_MAX / w, LOGO_MAX / h)
    new_w, new_h = int(w * scale), int(h * scale)
    logo = src.resize((new_w, new_h), Image.Resampling.LANCZOS)

    canvas = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
    x = (CANVAS - new_w) // 2
    y = (CANVAS - new_h) // 2
    canvas.paste(logo, (x, y), logo)
    canvas.save(OUT)
    print(f'Wrote {OUT} — logo {new_w}x{new_h} on {CANVAS}x{CANVAS} canvas')


if __name__ == '__main__':
    main()
