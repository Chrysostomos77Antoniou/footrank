from PIL import Image, ImageChops

img = Image.open("splash_clean.png").convert("RGB")
# Build a white background and diff to find the content bounding box.
bg = Image.new("RGB", img.size, (255, 255, 255))
diff = ImageChops.difference(img, bg)
bbox = diff.getbbox()
if bbox:
    # small padding around content
    pad = 24
    l, t, r, b = bbox
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(img.width, r + pad)
    b = min(img.height, b + pad)
    img.crop((l, t, r, b)).save("splash_trimmed.png")
    print("trimmed to", (r - l, b - t))
else:
    img.save("splash_trimmed.png")
    print("no content bbox; copied")
