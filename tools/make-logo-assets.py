#!/usr/bin/env python3
"""Make Ladrok TV artwork from the logo PNG (the silver Slash mark over LADROK on a dark background).

  python3 tools/make-logo-assets.py <logo.png> <aosp device/brcm/rpi5 dir> <repo public dir>

Writes:
  <device>/bootanimation/bootanimation.zip     fade-in of the logo on black, 1920x1080
  <device>/LadrokUpdater/res/drawable-nodpi/ic_launcher.png, banner.png
  <public>/logo.png                            for the README
The logo's dark background is turned into pure black by using brightness as coverage, so
the artwork has no visible box around it on a black TV screen.
"""
import io
import os
import sys
import zipfile

from PIL import Image, ImageChops

src, device_dir, public_dir = sys.argv[1:4]
img = Image.open(src).convert("L")

# Background level: median brightness of the four corners.
w, h = img.size
corners = []
for x0, y0 in ((0, 0), (w - 64, 0), (0, h - 64), (w - 64, h - 64)):
    corners += list(img.crop((x0, y0, x0 + 64, y0 + 64)).getdata())
bg = sorted(corners)[len(corners) // 2]
peak = max(img.getdata())
# Stretch [bg + margin, peak] to [0, 255]; everything at or below the background goes black.
lo = bg + 14
logo = img.point(lambda v: 0 if v <= lo else min(255, int((v - lo) * 255 / (peak - lo))))

# Bounding box from clearly bright pixels only, so faint background noise doesn't widen it.
solid = logo.point(lambda v: 255 if v > 90 else 0)
x0, y0, x1, y1 = solid.getbbox()
bbox = (max(0, x0 - 4), max(0, y0 - 4), min(w, x1 + 4), min(h, y1 + 4))
# Split the mark (the Slash) from the "LADROK" text at the empty rows between them.
rows = [max(solid.crop((bbox[0], y, bbox[2], y + 1)).getdata()) for y in range(bbox[1], bbox[3])]
gap = None
run = 0
for i, v in enumerate(rows):
    run = run + 1 if v == 0 else 0
    if run > 20:          # a 20+ px empty band inside the logo = between mark and text
        gap = bbox[1] + i
        break
full = logo.crop(bbox)
if gap:
    top = solid.crop((bbox[0], bbox[1], bbox[2], gap - 10))
    mx0, my0, mx1, my1 = top.getbbox()
    mark = logo.crop((bbox[0] + mx0 - 4, bbox[1] + my0 - 4, bbox[0] + mx1 + 4, bbox[1] + my1 + 4))
else:
    mark = full


def on_black(art, size, height_frac, y_center=0.5):
    """`art` scaled to height_frac of the canvas height, centred, on black."""
    W, H = size
    ah = int(H * height_frac)
    aw = int(art.width * ah / art.height)
    if aw > W * 0.9:
        aw = int(W * 0.9)
        ah = int(art.height * aw / art.width)
    a = art.resize((aw, ah), Image.LANCZOS)
    canvas = Image.new("L", size, 0)
    canvas.paste(a, ((W - aw) // 2, int(H * y_center - ah / 2)))
    return canvas


def save_png(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.convert("RGB").save(path, optimize=True)
    print("wrote", path, im.size)


# Boot animation: 1.3 s ease-in fade (part0, played once), then the logo held (part1, loops).
FRAMES = 40
base = on_black(full, (1920, 1080), 0.42)
zbuf = io.BytesIO()
with zipfile.ZipFile(zbuf, "w", zipfile.ZIP_STORED) as z:
    z.writestr("desc.txt", "1920 1080 30\np 1 0 part0\np 0 0 part1\n")
    for i in range(FRAMES):
        t = (i + 1) / FRAMES
        alpha = t * t * (3 - 2 * t)                       # smoothstep
        frame = base.point(lambda v: int(v * alpha))
        b = io.BytesIO()
        frame.convert("RGB").save(b, "PNG", optimize=True)
        z.writestr(f"part0/{i:05d}.png", b.getvalue())
    b = io.BytesIO()
    base.convert("RGB").save(b, "PNG", optimize=True)
    z.writestr("part1/00000.png", b.getvalue())
out = os.path.join(device_dir, "bootanimation", "bootanimation.zip")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "wb") as f:
    f.write(zbuf.getvalue())
print("wrote", out, len(zbuf.getvalue()), "bytes")

# Updater app: launcher icon (the mark) and TV launcher banner (full logo), 2x for xhdpi.
upd = os.path.join(device_dir, "LadrokUpdater", "res", "drawable-nodpi")
save_png(on_black(mark, (192, 192), 0.62), os.path.join(upd, "ic_launcher.png"))
save_png(on_black(full, (640, 360), 0.74), os.path.join(upd, "banner.png"))

# README logo
save_png(on_black(full, (640, 400), 0.80), os.path.join(public_dir, "logo.png"))
