#!/usr/bin/env python3
"""Generate the dgvault app icon for every platform.

The mark: a vault/safe door with a 'dg' combination dial in the terminal/hacker
aesthetic (mint-on-near-black, neon glow). One design, rendered into the shape
and file layout each platform expects:

  macOS   Assets.xcassets/AppIcon.appiconset/app_icon_*.png   (rounded, alpha)
  iOS     Assets.xcassets/AppIcon.appiconset/Icon-App-*.png    (square, NO alpha)
  Android mipmap-*/ic_launcher.png                             (square legacy)
          mipmap-*/ic_launcher_foreground.png + anydpi-v26     (adaptive)
  Windows runner/resources/app_icon.ico                        (multi-size)
  Linux   dgvault.png                                          (packaging)

Re-run after tweaking: `python3 tool/gen_icon.py`.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "JetBrainsMono-Bold.ttf")

# Palette (from lib/ui/theme/terminal_theme.dart).
DOOR = (13, 17, 23, 255)        # door face
PANEL = (17, 22, 31, 255)       # #11161F dial face
GREEN = (92, 242, 160, 255)     # #5CF2A0 primary mint
GREEN_DIM = (46, 125, 91, 255)  # #2E7D5B
TEXT = (224, 255, 240, 255)     # near-white mint for the wordmark
BG_TOP = (9, 12, 17, 255)
BG_BOT = (15, 19, 27, 255)
BG_HEX = "#0B0E14"              # Android adaptive background color


def _design(D):
    """The safe-door + dial + 'dg' mark on a TRANSPARENT background, DxD."""
    img = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    neon = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    nd = ImageDraw.Draw(neon)
    cx, cy = D / 2, D / 2

    # safe door frame (rounded square)
    door_inset = D * 0.16
    door_box = [door_inset, door_inset, D - door_inset, D - door_inset]
    door_radius = D * 0.10
    d.rounded_rectangle(door_box, door_radius, fill=DOOR)
    for layer, w in ((nd, D * 0.020), (d, D * 0.013)):
        layer.rounded_rectangle(door_box, door_radius, outline=GREEN,
                                width=max(1, int(w)))
    f2 = D * 0.205
    d.rounded_rectangle([f2, f2, D - f2, D - f2], door_radius * 0.7,
                        outline=GREEN_DIM, width=max(1, int(D * 0.006)))

    # corner bolts
    bolt_off, br = D * 0.225, D * 0.018
    for bx in (bolt_off, D - bolt_off):
        for by in (bolt_off, D - bolt_off):
            d.ellipse([bx - br, by - br, bx + br, by + br], fill=GREEN_DIM)

    # combination dial: tick marks
    R = D * 0.205
    ticks = 36
    for i in range(ticks):
        ang = math.radians(i * 360 / ticks - 90)
        major = i % 3 == 0
        r1 = R * (0.86 if major else 0.92)
        col = GREEN if major else GREEN_DIM
        w = D * (0.010 if major else 0.005)
        nd.line([cx + R * math.cos(ang), cy + R * math.sin(ang),
                 cx + r1 * math.cos(ang), cy + r1 * math.sin(ang)],
                fill=col, width=max(1, int(w)))
    # dial ring + face
    for layer, w in ((nd, D * 0.018), (d, D * 0.011)):
        layer.ellipse([cx - R, cy - R, cx + R, cy + R], outline=GREEN,
                      width=max(1, int(w)))
    rf = R * 0.80
    d.ellipse([cx - rf, cy - rf, cx + rf, cy + rf], fill=PANEL,
              outline=GREEN_DIM, width=max(1, int(D * 0.006)))

    # 'dg' wordmark centered in the dial
    font = ImageFont.truetype(FONT, int(R * 1.02))
    bbox = d.textbbox((0, 0), "dg", font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx, ty = cx - tw / 2 - bbox[0], cy - th / 2 - bbox[1]
    nd.text((tx, ty), "dg", font=font, fill=GREEN)
    d.text((tx, ty), "dg", font=font, fill=TEXT)

    # neon glow halo, then the crisp design on top
    glow = neon.filter(ImageFilter.GaussianBlur(D * 0.014))
    out = Image.alpha_composite(img, glow)
    out = Image.alpha_composite(out, glow)   # intensify
    out = Image.alpha_composite(out, img)    # crisp strokes over the glow
    return out


def _bg(D, rounded):
    """Background fill: rounded square (alpha corners) or full opaque square."""
    grad = Image.new("RGBA", (1, D), BG_TOP)
    gp = grad.load()
    for y in range(D):
        t = y / D
        gp[0, y] = tuple(round(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t)
                         for i in range(4))
    grad = grad.resize((D, D))
    if not rounded:
        return grad
    out = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    margin = D * 0.05
    mask = Image.new("L", (D, D), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [margin, margin, D - margin, D - margin], D * 0.225, fill=255)
    out.paste(grad, (0, 0), mask)
    return out


def compose(D, mode):
    """mode: 'rounded' (macOS), 'square' (iOS/Android/Win), 'foreground'."""
    if mode == "foreground":
        # Shrink the mark into the adaptive-icon safe zone so the door corners
        # survive a circular mask (key content within the central ~66dp/108dp).
        s = int(D * 0.70)
        design = _design(s)
        out = Image.new("RGBA", (D, D), (0, 0, 0, 0))
        out.paste(design, ((D - s) // 2, (D - s) // 2), design)
        return out
    return Image.alpha_composite(_bg(D, rounded=(mode == "rounded")),
                                 _design(D))


def _master(mode, size=1024):
    return compose(size, mode)


def _save(img, path, rgb=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if rgb:
        bg = Image.new("RGB", img.size, (11, 14, 20))
        bg.paste(img, mask=img.split()[3])
        bg.save(path)
    else:
        img.save(path)
    print("wrote", os.path.relpath(path, ROOT))


def gen_macos():
    base = os.path.join(ROOT, "macos", "Runner", "Assets.xcassets",
                        "AppIcon.appiconset")
    m = _master("rounded")
    for s in (16, 32, 64, 128, 256, 512, 1024):
        _save(m.resize((s, s), Image.LANCZOS),
              os.path.join(base, f"app_icon_{s}.png"))
    gen_macos_document()


def _document(D):
    """A Finder document icon: a dark page (folded corner) badged with the vault
    mark and a KDBX label, so .kdbx files read as dgvault vaults, DxD."""
    img = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Portrait page, centered, with a little breathing room.
    mx, top, bot = D * 0.17, D * 0.06, D * 0.06
    left, right = mx, D - mx
    fold = D * 0.20  # folded-corner size (top-right)
    radius = max(1, int(D * 0.045))

    # Page body (rounded), with the top-right corner cut for the fold.
    page = [left, top, right, D - bot]
    d.rounded_rectangle(page, radius, fill=DOOR, outline=GREEN_DIM,
                        width=max(1, int(D * 0.006)))
    # Mask off the corner and redraw the fold as a lighter triangle.
    d.polygon([(right - fold, top), (right, top), (right, top + fold)],
              fill=(0, 0, 0, 0))
    d.polygon([(right - fold, top), (right, top + fold),
               (right - fold, top + fold)], fill=PANEL, outline=GREEN,
              width=max(1, int(D * 0.005)))
    d.line([(right - fold, top), (right - fold, top + fold),
            (right, top + fold)], fill=GREEN, width=max(1, int(D * 0.005)))

    # Vault mark badged in the upper half of the page.
    s = int((right - left) * 0.66)
    mark = _design(s)
    img.alpha_composite(mark, (int((D - s) / 2), int(top + D * 0.10)))

    # "KDBX" wordmark along the bottom of the page.
    font = ImageFont.truetype(FONT, int(D * 0.13))
    bbox = d.textbbox((0, 0), "KDBX", font=font)
    tw = bbox[2] - bbox[0]
    d.text(((D - tw) / 2 - bbox[0], D - bot - D * 0.20), "KDBX",
           font=font, fill=GREEN)
    return img


def gen_macos_document():
    """Write macos/Runner/DocumentIcon.icns (Finder icon for .kdbx files)."""
    import shutil
    import subprocess
    if not shutil.which("iconutil"):
        print("skip DocumentIcon.icns (no iconutil — macOS only)")
        return
    runner = os.path.join(ROOT, "macos", "Runner")
    iconset = os.path.join(runner, "DocumentIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    master = _document(1024)
    # Apple's required iconset members (1x + @2x).
    for base_px, name in ((16, "16x16"), (32, "32x32"), (128, "128x128"),
                          (256, "256x256"), (512, "512x512")):
        master.resize((base_px, base_px), Image.LANCZOS).save(
            os.path.join(iconset, f"icon_{name}.png"))
        master.resize((base_px * 2, base_px * 2), Image.LANCZOS).save(
            os.path.join(iconset, f"icon_{name}@2x.png"))
    out = os.path.join(runner, "DocumentIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)
    shutil.rmtree(iconset)
    print("wrote", os.path.relpath(out, ROOT))


def gen_ios():
    base = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets",
                        "AppIcon.appiconset")
    if not os.path.isdir(base):
        return
    m = _master("square")
    # filename -> pixel size (App Store icons must be opaque, no alpha)
    icons = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60, "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120, "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180, "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152, "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, px in icons.items():
        _save(m.resize((px, px), Image.LANCZOS),
              os.path.join(base, name), rgb=True)


def gen_android():
    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    if not os.path.isdir(res):
        return
    legacy = _master("square")
    fg = _master("foreground")
    # density -> (legacy px, adaptive foreground px @108dp)
    dens = {"mdpi": (48, 108), "hdpi": (72, 162), "xhdpi": (96, 216),
            "xxhdpi": (144, 324), "xxxhdpi": (192, 432)}
    for name, (lpx, fpx) in dens.items():
        d = os.path.join(res, f"mipmap-{name}")
        _save(legacy.resize((lpx, lpx), Image.LANCZOS),
              os.path.join(d, "ic_launcher.png"))
        _save(fg.resize((fpx, fpx), Image.LANCZOS),
              os.path.join(d, "ic_launcher_foreground.png"))


def gen_ios_document():
    """iOS document-type icons (shown in Files) → ios/Runner/DocumentIcons/."""
    base = os.path.join(ROOT, "ios", "Runner")
    if not os.path.isdir(base):
        return
    out = os.path.join(base, "DocumentIcons")
    os.makedirs(out, exist_ok=True)
    master = _document(1024)
    # CFBundleTypeIconFiles picks the best match; provide 64pt & 320pt @1x/@2x/@3x.
    for pt in (64, 320):
        for scale in (1, 2, 3):
            px = pt * scale
            suffix = "" if scale == 1 else f"@{scale}x"
            master.resize((px, px), Image.LANCZOS).save(
                os.path.join(out, f"kdbx_doc_{pt}{suffix}.png"))
    print("wrote", os.path.relpath(out, ROOT) + "/kdbx_doc_*.png")


def gen_windows():
    resdir = os.path.join(ROOT, "windows", "runner", "resources")
    if not os.path.isdir(resdir):
        return
    m = _master("square", 256)
    m.save(os.path.join(resdir, "app_icon.ico"), format="ICO",
           sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64),
                  (128, 128), (256, 256)])
    print("wrote windows/runner/resources/app_icon.ico")
    # Document icon for the .kdbx association (installer sets DefaultIcon → this).
    doc = _document(256)
    doc.save(os.path.join(resdir, "kdbx_document.ico"), format="ICO",
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64),
                    (128, 128), (256, 256)])
    print("wrote windows/runner/resources/kdbx_document.ico")


def gen_linux():
    if not os.path.isdir(os.path.join(ROOT, "linux")):
        return
    m = _master("rounded")
    _save(m.resize((512, 512), Image.LANCZOS),
          os.path.join(ROOT, "linux", "dgvault.png"))
    # MIME-type icon: freedesktop names it after the type (slashes → dashes),
    # so the file manager shows it for every .kdbx file. Installed into
    # hicolor/<size>/mimetypes/. .kdbx is the de-facto application/x-keepass2.
    doc = _document(512)
    packaging = os.path.join(ROOT, "linux", "packaging", "icons")
    for s in (16, 24, 32, 48, 64, 128, 256, 512):
        _save(doc.resize((s, s), Image.LANCZOS),
              os.path.join(packaging, f"{s}x{s}", "mimetypes",
                           "application-x-keepass2.png"))


def main():
    gen_macos()
    gen_ios()
    gen_ios_document()
    gen_android()
    gen_windows()
    gen_linux()


if __name__ == "__main__":
    main()
