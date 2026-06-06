from PIL import Image

img = Image.open("splash.png").convert("RGBA")
w, h = img.size
# Keep only the top lockup (logo + FootRank + tagline); drop the bottom mini-logos.
cropped = img.crop((0, 0, w, int(h * 0.62)))
cropped.save("splash_clean.png")
print("saved splash_clean.png", cropped.size)
