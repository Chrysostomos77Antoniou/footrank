from PIL import Image, ImageDraw
from collections import Counter
import sys

src = "app_icon.png"
img = Image.open(src).convert("RGB")
w, h = img.size

px = img.load()

def is_white(c, t=235):
    return c[0] >= t and c[1] >= t and c[2] >= t

# Find the dominant green (most common non-white, non-black color)
counts = Counter()
for y in range(0, h, 4):
    for x in range(0, w, 4):
        c = px[x, y]
        if is_white(c):
            continue
        if c[0] < 40 and c[1] < 40 and c[2] < 40:
            continue
        # bucket to reduce noise
        counts[(c[0] // 8 * 8, c[1] // 8 * 8, c[2] // 8 * 8)] += 1

green = counts.most_common(1)[0][0]
print("detected green:", green)

# Flood fill the edge-connected white background with green from all 4 corners.
for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
    if is_white(px[seed[0], seed[1]]):
        ImageDraw.floodfill(img, seed, green, thresh=60)

img.save(src)
print("saved full-bleed icon", img.size)
