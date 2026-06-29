#!/usr/bin/env python3
"""Generate the dgvault app icon: a vault/safe door with a 'dg' combination
dial in the terminal/hacker aesthetic (mint-on-near-black, neon glow).

Renders at high resolution with supersampling, then writes every macOS
AppIcon size. Re-run after tweaking: `python3 tool/gen_icon.py`.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "JetBrainsMono-Bold.ttf")
OUT_DIR = os.path.join(
    ROOT, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset"
)

# Palette (from lib/ui/theme/terminal_theme.dart).
BG = (11, 14, 20, 255)        # #0B0E14
DOOR = (13, 17, 23, 255)      # door face
PANEL = (17, 22, 31, 255)     # #11161F dial face
GREEN = (92, 242, 160, 255)   # #5CF2A0 primary mint
GREEN_DIM = (46, 125, 91, 255)  # #2E7D5B
CYAN = (86, 197, 214, 255)    # #56C5D6


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(4))


def draw_icon(D):
    """Draw the icon on a DxD RGBA canvas."""
    img = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    margin = D * 0.05
    bg_box = [margin, margin, D - margin, D - margin]
    bg_radius = D * 0.225
    # Background squircle with a faint vertical gradient for depth.
    grad = Image.new("RGBA", (1, D), BG)
    gp = grad.load()
    for y in range(D):
        gp[0, y] = lerp((9, 12, 17, 255), (15, 19, 27, 255), y / D)
    grad = grad.resize((D, D))
    mask = Image.new("L", (D, D), 0)
    ImageDraw.Draw(mask).rounded_rectangle(bg_box, bg_radius, fill=255)
    img.paste(grad, (0, 0), mask)

    # Neon layer (blurred later for the glow halo).
    neon = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    nd = ImageDraw.Draw(neon)

    cx, cy = D / 2, D / 2

    # --- safe door frame (rounded square) -------------------------------
    door_inset = D * 0.16
    door_box = [door_inset, door_inset, D - door_inset, D - door_inset]
    door_radius = D * 0.10
    d.rounded_rectangle(door_box, door_radius, fill=DOOR)
    for layer, w in ((nd, D * 0.020), (d, D * 0.013)):
        layer.rounded_rectangle(door_box, door_radius, outline=GREEN,
                                width=max(1, int(w)))
    # inner double-line frame (terminal box-draw vibe)
    f2 = D * 0.205
    d.rounded_rectangle([f2, f2, D - f2, D - f2], door_radius * 0.7,
                        outline=GREEN_DIM, width=max(1, int(D * 0.006)))

    # corner bolts
    bolt_off = D * 0.225
    br = D * 0.018
    for bx in (bolt_off, D - bolt_off):
        for by in (bolt_off, D - bolt_off):
            d.ellipse([bx - br, by - br, bx + br, by + br], fill=GREEN_DIM)

    # --- combination dial ----------------------------------------------
    R = D * 0.205
    # tick marks around the dial
    ticks = 36
    for i in range(ticks):
        ang = math.radians(i * 360 / ticks - 90)
        major = i % 3 == 0
        r0 = R * (1.0)
        r1 = R * (0.86 if major else 0.92)
        col = GREEN if major else GREEN_DIM
        w = D * (0.010 if major else 0.005)
        x0, y0 = cx + r0 * math.cos(ang), cy + r0 * math.sin(ang)
        x1, y1 = cx + r1 * math.cos(ang), cy + r1 * math.sin(ang)
        nd.line([x0, y0, x1, y1], fill=col, width=max(1, int(w)))

    # dial outer ring
    for layer, w in ((nd, D * 0.018), (d, D * 0.011)):
        layer.ellipse([cx - R, cy - R, cx + R, cy + R], outline=GREEN,
                      width=max(1, int(w)))
    # dial face
    rf = R * 0.80
    d.ellipse([cx - rf, cy - rf, cx + rf, cy + rf], fill=PANEL,
              outline=GREEN_DIM, width=max(1, int(D * 0.006)))

    # --- 'dg' wordmark in the dial -------------------------------------
    text = "dg"
    fs = int(R * 1.02)
    font = ImageFont.truetype(FONT, fs)
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = cx - tw / 2 - bbox[0]
    ty = cy - th / 2 - bbox[1]
    nd.text((tx, ty), text, font=font, fill=GREEN)
    # crisp text with a faint cyan underglow for a CRT feel
    d.text((tx, ty), text, font=font, fill=(220, 255, 238, 255))

    # --- composite glow -------------------------------------------------
    glow = neon.filter(ImageFilter.GaussianBlur(D * 0.014))
    out = Image.alpha_composite(img, glow)
    out = Image.alpha_composite(out, glow)  # intensify
    # redraw crisp strokes on top of the glow
    out = Image.alpha_composite(out, _crisp_overlay(D))
    return out


def _crisp_overlay(D):
    """The crisp foreground (re-drawn so the glow doesn't wash it out)."""
    img = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = D / 2, D / 2

    door_inset = D * 0.16
    door_box = [door_inset, door_inset, D - door_inset, D - door_inset]
    d.rounded_rectangle(door_box, D * 0.10, outline=GREEN,
                        width=max(1, int(D * 0.013)))
    R = D * 0.205
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=GREEN,
              width=max(1, int(D * 0.011)))
    rf = R * 0.80
    d.ellipse([cx - rf, cy - rf, cx + rf, cy + rf], outline=GREEN_DIM,
              width=max(1, int(D * 0.006)))

    text = "dg"
    fs = int(R * 1.02)
    font = ImageFont.truetype(FONT, fs)
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = cx - tw / 2 - bbox[0]
    ty = cy - th / 2 - bbox[1]
    d.text((tx, ty), text, font=font, fill=(224, 255, 240, 255))
    return img


def main():
    SS = 2048  # supersample master
    master = draw_icon(SS)
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes:
        out = master.resize((s, s), Image.LANCZOS)
        path = os.path.join(OUT_DIR, f"app_icon_{s}.png")
        out.save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
