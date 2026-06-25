#!/usr/bin/env python3
"""Génère l'icône de l'app Sillon (Concept « vinyle ») dans l'asset catalog.

Conçue maison → originale et libre de droits. Motif : disque vinyle + sillons (le nom de l'app) +
double note de musique, dans la palette de l'app (cuivre / teal / sombre). Deux variantes :
- foncée  -> apparence sombre (UIAppearanceDark)
- claire  -> apparence claire / défaut

Dépendance : Pillow (`pip install Pillow`). Dessin raster (pas de toolchain SVG/cairo requise).
Usage : python3 Tools/generate_app_icon.py
"""
from PIL import Image, ImageDraw
import math, os

SS = 3                      # sur-échantillonnage pour l'antialiasing
S = 1024 * SS
ICON_DIR = os.path.join(os.path.dirname(__file__), "..", "Sillon", "Assets.xcassets", "AppIcon.appiconset")

COPPER  = (217, 142, 74)
COPPERD = (176, 103, 44)
FOND    = (11, 13, 15)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def radial(inner, outer):
    img = Image.new("RGB", (S, S), outer)
    d = ImageDraw.Draw(img)
    cx = cy = S / 2
    maxr = math.hypot(cx, cy)
    for i in range(300, 0, -1):
        t = i / 300
        r = maxr * t
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=lerp(inner, outer, t))
    return img


def diagonal_sheen(img, cx, cy, R, alpha):
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([cx - R, cy - R, cx + R, cy + R], fill=(255, 255, 255, alpha))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon([(cx - R, cy - R), (cx + R * 0.3, cy - R), (cx - R, cy + R * 0.3)], fill=255)
    img.paste(sh, (0, 0), Image.composite(sh.split()[3], Image.new("L", (S, S), 0), mask))


def rot_ellipse(img, cx, cy, w, h, ang, color):
    pad = int(max(w, h) * 1.8)
    e = Image.new("RGBA", (pad, pad), (0, 0, 0, 0))
    ImageDraw.Draw(e).ellipse([pad / 2 - w / 2, pad / 2 - h / 2, pad / 2 + w / 2, pad / 2 + h / 2], fill=color)
    e = e.rotate(ang, resample=Image.BICUBIC, expand=False)
    img.paste(e, (int(cx - pad / 2), int(cy - pad / 2)), e)


def beamed_notes(img, cx, cy, sc, color):
    d = ImageDraw.Draw(img, "RGBA")
    head_w, head_h, stem_w, stem_h, gap, beam_h = 1.05 * sc, 0.72 * sc, 0.17 * sc, 2.7 * sc, 2.0 * sc, 0.46 * sc
    lx, rx, hy = cx - gap / 2, cx + gap / 2, cy + sc * 1.15
    rot_ellipse(img, lx, hy, head_w, head_h, 22, color)
    rot_ellipse(img, rx, hy, head_w, head_h, 22, color)
    sxl, sxr, topy = lx + head_w * 0.40, rx + head_w * 0.40, hy - stem_h
    d.rounded_rectangle([sxl - stem_w / 2, topy, sxl + stem_w / 2, hy - head_h * 0.1], radius=stem_w * 0.4, fill=color)
    d.rounded_rectangle([sxr - stem_w / 2, topy, sxr + stem_w / 2, hy - head_h * 0.1], radius=stem_w * 0.4, fill=color)
    d.polygon([(sxl - stem_w / 2, topy), (sxr + stem_w / 2, topy - 0.18 * sc),
               (sxr + stem_w / 2, topy + beam_h - 0.18 * sc), (sxl - stem_w / 2, topy + beam_h)], fill=color)


def make(dark: bool):
    cx = cy = S / 2
    R, label_r = S * 0.42, S * 0.14
    if dark:
        img = radial((24, 19, 16), FOND)
        disc, groove, label, hole, note = (14, 14, 17), (58, 92, 90), COPPERD, FOND, COPPER
    else:
        img = radial((250, 247, 240), (238, 233, 224))
        disc, groove, label, hole, note = (228, 223, 214), (38, 110, 103), COPPER, (238, 233, 224), COPPER
    d = ImageDraw.Draw(img, "RGBA")
    d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=disc)
    diagonal_sheen(img, cx, cy, R, 90 if not dark else 16)
    for i in range(18):
        r = label_r + (R - label_r) * (i + 1) / 19
        a = 1 - 0.35 * (i / 18)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=tuple(groove) + (int((150 if not dark else 230) * a),),
                  width=max(1, int(1.6 * SS)))
    d.ellipse([cx - label_r, cy - label_r, cx + label_r, cy + label_r], fill=label)
    hr = label_r * 0.13
    d.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=hole)
    beamed_notes(img, S * 0.62, S * 0.66, S * 0.060, note)
    return img.resize((1024, 1024), Image.LANCZOS)


def main():
    dark = make(True)
    light = make(False)
    dark.save(os.path.join(ICON_DIR, "AppIcon-ios-dark.png"))
    light.save(os.path.join(ICON_DIR, "AppIcon-ios-light.png"))
    sizes = {"mac-16.png": 16, "mac-16@2x.png": 32, "mac-32.png": 32, "mac-32@2x.png": 64,
             "mac-128.png": 128, "mac-128@2x.png": 256, "mac-256.png": 256, "mac-256@2x.png": 512,
             "mac-512.png": 512, "mac-512@2x.png": 1024}
    for fn, px in sizes.items():
        dark.resize((px, px), Image.LANCZOS).save(os.path.join(ICON_DIR, fn))
    print("Icône générée dans", os.path.normpath(ICON_DIR))


if __name__ == "__main__":
    main()
