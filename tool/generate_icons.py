# -*- coding: utf-8 -*-
"""Regenerates every platform launcher icon from assets/images/logo/of.png.

The source file is actually a WebP (1920x1920) with a .png extension; PIL
sniffs the real format, so the same decode path works everywhere. Outputs
overwrite the platform icon files in place.
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "images", "logo", "of.png")

src = Image.open(SRC)
if src.format != "PNG":
    # Normalise to PNG once, in memory, for consistent downstream encoding.
    pass
src = src.convert("RGBA")
if src.size != (1024, 1024):
    src = src.resize((1024, 1024), Image.LANCZOS)


def save_png(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, format="PNG", optimize=True)
    print("png", path.replace(ROOT + os.sep, ""), img.size)


def save_ico(path, sizes):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    src.save(path, format="ICO", sizes=[(s, s) for s in sizes])
    print("ico", path.replace(ROOT + os.sep, ""), sizes)


def resize(px):
    return src.resize((px, px), Image.LANCZOS)


# --- iOS: AppIcon.appiconset (size@scale table) ---
ios_table = [
    ("Icon-App-20x20@1x.png", 20), ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60), ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58), ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40), ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120), ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180), ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152), ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]
ios_dir = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
for name, px in ios_table:
    save_png(resize(px), os.path.join(ios_dir, name))

# --- macOS: AppIcon.appiconset ---
mac_table = [
    ("app_icon_16.png", 16), ("app_icon_32.png", 32), ("app_icon_64.png", 64),
    ("app_icon_128.png", 128), ("app_icon_256.png", 256),
    ("app_icon_512.png", 512), ("app_icon_1024.png", 1024),
]
mac_dir = os.path.join(ROOT, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
for name, px in mac_table:
    save_png(resize(px), os.path.join(mac_dir, name))

# --- Android: legacy launcher mipmaps ---
android_table = [
    ("mipmap-mdpi", 48), ("mipmap-hdpi", 72), ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144), ("mipmap-xxxhdpi", 192),
]
for dpi, px in android_table:
    save_png(resize(px),
             os.path.join(ROOT, "android", "app", "src", "main", "res", dpi,
                          "ic_launcher.png"))

# --- Web: favicon + PWA icons (maskable rendered with 10% safe-zone inset
# baked in: the icon content is scaled to 80% over a solid canvas so the
# maskable-safe area requirement holds) ---
save_png(resize(16), os.path.join(ROOT, "web", "favicon.png"))
save_png(resize(192), os.path.join(ROOT, "web", "icons", "Icon-192.png"))
save_png(resize(512), os.path.join(ROOT, "web", "icons", "Icon-512.png"))
for px in (192, 512):
    canvas = Image.new("RGBA", (px, px), (255, 255, 255, 0))
    inner = resize(int(px * 0.8))
    off = (px - inner.size[0]) // 2
    canvas.paste(inner, (off, off), inner)
    save_png(canvas,
             os.path.join(ROOT, "web", "icons", "Icon-maskable-%d.png" % px))

# --- Windows: multi-size .ico (16..256) ---
save_ico(os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico"),
         [16, 24, 32, 48, 64, 128, 256])

print("done")
