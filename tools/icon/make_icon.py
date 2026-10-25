#!/usr/bin/env python3
"""Builds the Star Battles app icon from code.

Writes the master icon.svg plus every raster the exports need:
  assets/icon/icon_1024.png           master raster (project / store art)
  assets/icon/android_main_192.png    legacy launcher icon
  assets/icon/android_fg_432.png      adaptive foreground (ship, safe zone)
  assets/icon/android_bg_432.png      adaptive background (space + Saturn)
  assets/icon/android_mono_432.png    themed (monochrome) icon
  assets/icon/icon.ico                Windows exe icon (16..256)

Run from the repo root:  python3 tools/icon/make_icon.py   (needs cairosvg + Pillow)
"""
import io
import math
import os

import cairosvg
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "icon")

# Silverwing, top view, nose up. Right half only (x >= 0); mirrored for the left.
# Units: the hull spans y -100 (nose) .. +62 (nozzles), x -84 .. 84.
HULL_R = [
    (0, -104), (4, -84), (8, -60), (12, -34), (15, -16),
    (22, -8), (58, 22), (80, 38), (84, 44), (84, 50),
    (64, 48), (34, 40), (27, 44), (26, 60), (8, 60), (6, 52), (0, 50),
]
COCKPIT_R = [(0, -80), (3.4, -64), (5.2, -44), (4.6, -30), (0, -24)]
STRIPE_R = [(0, -24), (6, -24), (11, -6), (6, 8), (0, 8)]
WING_FLASH_R = [(30, 4), (60, 28), (76, 40), (68, 40), (46, 28), (28, 14)]


def mirror(pts):
    return [(-x, y) for x, y in reversed(pts)]


def path(pts, close=True):
    d = "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in pts)
    return d + (" Z" if close else "")


def half(pts):
    """Closed path of one hull half (right half as given, closed on the spine)."""
    return path(pts)


def full(pts):
    return path(pts + mirror(pts)[1:-1])


def ship(mono=False):
    """Ship group in hull units, nose pointing up, centred near (0, -20)."""
    if mono:
        guns = "".join(
            f'<rect x="{s * 84 - 5.5:.1f}" y="-8" width="11" height="54" rx="2" fill="#fff"/>'
            f'<circle cx="{s * 84}" cy="44" r="9" fill="#fff"/>'
            for s in (-1, 1))
        plumes = "".join(f'<path d="M{ex - 8} 56 L{ex + 8} 56 L{ex + 2} 120 L{ex - 2} 120 Z" fill="#fff"/>'
                         for ex in (-17, 17))
        return f'<path d="{full(HULL_R)}" fill="#fff"/>{guns}{plumes}'

    left = mirror(HULL_R)
    s = []
    # Engine plumes (drawn first so the hull sits on top).
    for ex in (-17, 17):
        s.append(f'<path d="M{ex - 10} 56 L{ex + 10} 56 L{ex + 3} 230 L{ex - 3} 230 Z" fill="url(#plume)"/>')
        s.append(f'<ellipse cx="{ex}" cy="74" rx="13" ry="30" fill="url(#plumeCore)"/>')
    # Soft drop glow under the hull so it separates from the planet.
    s.append(f'<path d="{full(HULL_R)}" fill="#000" opacity="0.55" filter="url(#drop)" transform="translate(0 6)"/>')
    # Hull: lit left half, shaded right half, then an edge rim.
    s.append(f'<path d="{half(left)}" fill="url(#hullLit)"/>')
    s.append(f'<path d="{half(HULL_R)}" fill="url(#hullDark)"/>')
    s.append(f'<path d="{path(WING_FLASH_R)}" fill="#2fb8ff" opacity="0.85"/>')
    s.append(f'<path d="{path(mirror(WING_FLASH_R))}" fill="#7fd6ff" opacity="0.9"/>')
    s.append('<path d="M0 -30 L5 -20 L4 40 L0 46 L-4 40 L-5 -20 Z" fill="#d7e2f2" opacity="0.55"/>')
    s.append(f'<path d="{full(COCKPIT_R)}" fill="url(#canopy)"/>')
    s.append('<path d="M-1.2 -76 L-3.4 -50 L-1 -34 Z" fill="#e8fbff" opacity="0.9"/>')
    # Panel lines.
    s.append('<g stroke="#0d1420" stroke-width="1.1" opacity="0.55" fill="none">'
             '<path d="M0 -24 L0 50"/><path d="M15 -16 L27 44"/><path d="M-15 -16 L-27 44"/>'
             '<path d="M24 -2 L34 40"/><path d="M-24 -2 L-34 40"/></g>')
    s.append(f'<path d="{full(HULL_R)}" fill="none" stroke="url(#rim)" stroke-width="2.2" stroke-linejoin="round"/>')
    # Nozzles.
    for ex in (-17, 17):
        s.append(f'<rect x="{ex - 9}" y="52" width="18" height="9" rx="2" fill="#2a3345"/>')
        s.append(f'<ellipse cx="{ex}" cy="61" rx="8" ry="3.4" fill="#e9fbff"/>')
    # Wingtip cannons + muzzle flashes and bolts.
    for sx in (-1, 1):
        x = sx * 84
        s.append(f'<path d="M{x} -128 L{x + 2.6} -40 L{x} -26 L{x - 2.6} -40 Z" fill="url(#bolt)"/>')
        s.append(f'<rect x="{x - 4}" y="-4" width="8" height="50" rx="2" fill="#5b6880"/>')
        s.append(f'<rect x="{x - 4}" y="-4" width="4" height="50" rx="1.5" fill="#dfe7f2"/>')
        s.append(f'<rect x="{x - 5.5}" y="-8" width="11" height="7" rx="1.5" fill="#2a3345"/>')
        s.append(f'<circle cx="{x}" cy="44" r="9" fill="url(#pod)"/>')
        s.append(f'<circle cx="{x}" cy="-12" r="11" fill="url(#flash)"/>')
    return "".join(s)


DEFS = """
<defs>
  <radialGradient id="space" cx="38%" cy="30%" r="85%">
    <stop offset="0" stop-color="#16244a"/>
    <stop offset="0.45" stop-color="#0a1128"/>
    <stop offset="1" stop-color="#020309"/>
  </radialGradient>
  <radialGradient id="nebBlue" cx="50%" cy="50%" r="50%">
    <stop offset="0" stop-color="#2a7bff" stop-opacity="0.55"/>
    <stop offset="1" stop-color="#2a7bff" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="nebOrange" cx="50%" cy="50%" r="50%">
    <stop offset="0" stop-color="#ff6a2a" stop-opacity="0.42"/>
    <stop offset="1" stop-color="#ff6a2a" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="planet" cx="30%" cy="25%" r="80%">
    <stop offset="0" stop-color="#fbe7b9"/>
    <stop offset="0.35" stop-color="#e0b874"/>
    <stop offset="0.75" stop-color="#8a5a2a"/>
    <stop offset="1" stop-color="#2a170a"/>
  </radialGradient>
  <linearGradient id="bands" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0"/>
    <stop offset="0.3" stop-color="#7a4a1e" stop-opacity="0.35"/>
    <stop offset="0.38" stop-color="#fff3d6" stop-opacity="0.25"/>
    <stop offset="0.55" stop-color="#6a3c16" stop-opacity="0.3"/>
    <stop offset="0.7" stop-color="#fff" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="ring" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#f1dcae" stop-opacity="0"/>
    <stop offset="0.25" stop-color="#f1dcae" stop-opacity="0.95"/>
    <stop offset="0.7" stop-color="#c79c62" stop-opacity="0.85"/>
    <stop offset="1" stop-color="#c79c62" stop-opacity="0"/>
  </linearGradient>
  <radialGradient id="atmo" cx="50%" cy="50%" r="50%">
    <stop offset="0.86" stop-color="#ffcf8a" stop-opacity="0"/>
    <stop offset="0.95" stop-color="#ffd9a0" stop-opacity="0.5"/>
    <stop offset="1" stop-color="#ffd9a0" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="hullLit" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#ffffff"/>
    <stop offset="0.5" stop-color="#dfe7f2"/>
    <stop offset="1" stop-color="#9eacc2"/>
  </linearGradient>
  <linearGradient id="hullDark" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#a9b6ca"/>
    <stop offset="0.6" stop-color="#6c7a92"/>
    <stop offset="1" stop-color="#3a4558"/>
  </linearGradient>
  <linearGradient id="rim" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#ffffff" stop-opacity="0.95"/>
    <stop offset="0.6" stop-color="#bcd4ff" stop-opacity="0.35"/>
    <stop offset="1" stop-color="#22304a" stop-opacity="0.6"/>
  </linearGradient>
  <linearGradient id="canopy" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#bff0ff"/>
    <stop offset="0.4" stop-color="#3ab4ff"/>
    <stop offset="1" stop-color="#0a3a8a"/>
  </linearGradient>
  <linearGradient id="plume" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#9ee8ff" stop-opacity="0.95"/>
    <stop offset="0.25" stop-color="#3aa8ff" stop-opacity="0.6"/>
    <stop offset="1" stop-color="#2a5cff" stop-opacity="0"/>
  </linearGradient>
  <radialGradient id="plumeCore" cx="50%" cy="20%" r="80%">
    <stop offset="0" stop-color="#ffffff"/>
    <stop offset="0.35" stop-color="#8fe4ff" stop-opacity="0.9"/>
    <stop offset="1" stop-color="#2a7bff" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="bolt" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#7fe0ff" stop-opacity="0"/>
    <stop offset="0.6" stop-color="#9fe9ff" stop-opacity="0.9"/>
    <stop offset="1" stop-color="#ffffff"/>
  </linearGradient>
  <radialGradient id="pod">
    <stop offset="0" stop-color="#ffd1b8"/>
    <stop offset="0.6" stop-color="#ff6a3a"/>
    <stop offset="1" stop-color="#8a1e10"/>
  </radialGradient>
  <radialGradient id="flash">
    <stop offset="0" stop-color="#ffffff"/>
    <stop offset="0.4" stop-color="#9fe9ff" stop-opacity="0.8"/>
    <stop offset="1" stop-color="#3aa8ff" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="vignette" cx="50%" cy="50%" r="72%">
    <stop offset="0.6" stop-color="#000" stop-opacity="0"/>
    <stop offset="1" stop-color="#000" stop-opacity="0.55"/>
  </radialGradient>
  <filter id="drop" x="-50%" y="-50%" width="200%" height="200%">
    <feGaussianBlur stdDeviation="5"/>
  </filter>
  <clipPath id="planetClip"><circle cx="0" cy="0" r="300"/></clipPath>
</defs>
"""


def stars(n, size, seed=7):
    import random
    rnd = random.Random(seed)
    out = []
    for _ in range(n):
        x, y = rnd.uniform(0, size), rnd.uniform(0, size)
        r = rnd.choice([0.9, 1.2, 1.5, 1.9, 2.6]) * size / 512
        a = rnd.uniform(0.35, 1.0)
        c = rnd.choice(["#ffffff", "#ffffff", "#cfe6ff", "#ffe6cf"])
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.2f}" fill="{c}" opacity="{a:.2f}"/>')
    # A few sparkles.
    for x, y, r in ((0.16, 0.2, 9), (0.83, 0.13, 6), (0.1, 0.62, 5)):
        x, y, r = x * size, y * size, r * size / 512
        out.append(f'<path d="M{x} {y - r} L{x + r * 0.18} {y} L{x} {y + r} L{x - r * 0.18} {y} Z" fill="#fff" opacity="0.85"/>'
                   f'<path d="M{x - r} {y} L{x} {y + r * 0.18} L{x + r} {y} L{x} {y - r * 0.18} Z" fill="#fff" opacity="0.85"/>')
    return "".join(out)


def backdrop(size):
    """Space, team-coloured nebulae and a ringed Saturn in the lower right."""
    k = size / 512.0
    return (
        f'<rect width="{size}" height="{size}" fill="url(#space)"/>'
        f'<ellipse cx="{120 * k}" cy="{400 * k}" rx="{260 * k}" ry="{200 * k}" fill="url(#nebBlue)"/>'
        f'<ellipse cx="{430 * k}" cy="{90 * k}" rx="{220 * k}" ry="{170 * k}" fill="url(#nebOrange)"/>'
        + stars(70, size) +
        f'<g transform="translate({405 * k} {418 * k}) scale({k}) rotate(-28)">'
        '<clipPath id="pc"><circle r="140"/></clipPath>'
        # back half of the ring
        '<path d="M-262 0 A262 54 0 0 1 262 0" fill="none" stroke="url(#ring)" stroke-width="20" opacity="0.75"/>'
        '<path d="M-226 0 A226 44 0 0 1 226 0" fill="none" stroke="url(#ring)" stroke-width="9" opacity="0.55"/>'
        '<circle r="140" fill="url(#planet)"/>'
        '<rect x="-140" y="-140" width="280" height="280" fill="url(#bands)" clip-path="url(#pc)"/>'
        '<circle r="146" fill="url(#atmo)"/>'
        # ring shadow on the planet, then the front half of the ring
        '<path d="M-140 18 A190 34 0 0 0 140 18" fill="none" stroke="#1a0d04" stroke-width="14" opacity="0.35" clip-path="url(#pc)"/>'
        '<path d="M-262 0 A262 54 0 0 0 262 0" fill="none" stroke="url(#ring)" stroke-width="20"/>'
        '<path d="M-226 0 A226 44 0 0 0 226 0" fill="none" stroke="url(#ring)" stroke-width="9" opacity="0.8"/>'
        '<path d="M-248 4 A248 50 0 0 0 248 4" fill="none" stroke="#fff4dc" stroke-width="2" opacity="0.55"/>'
        '</g>'
    )


def ship_layer(size, scale, cx, cy, angle=42, mono=False):
    k = size / 512.0
    return (f'<g transform="translate({cx * k} {cy * k}) rotate({angle}) scale({scale * k}) translate(0 20)">'
            + ship(mono) + '</g>')


def svg(size, body, rounded=False):
    clip = ""
    if rounded:
        r = size * 0.2
        clip = f'<clipPath id="round"><rect width="{size}" height="{size}" rx="{r}"/></clipPath>'
        body = f'<g clip-path="url(#round)">{body}</g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 {size} {size}">{DEFS}{clip}{body}</svg>')


def vignette(size):
    return f'<rect width="{size}" height="{size}" fill="url(#vignette)"/>'


def master(rounded):
    s = 512
    return svg(s, backdrop(s) + ship_layer(s, 1.62, 246, 262) + vignette(s), rounded)


def render(svg_text, px):
    png = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=px, output_height=px)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def main():
    os.makedirs(OUT, exist_ok=True)
    rounded = master(True)
    square = master(False)
    with open(os.path.join(ROOT, "icon.svg"), "w") as f:
        f.write(rounded)
    render(rounded, 1024).save(os.path.join(OUT, "icon_1024.png"))
    render(square, 192).save(os.path.join(OUT, "android_main_192.png"))

    # Adaptive icon: 108dp canvas, launcher masks to the inner ~72dp, so the
    # ship sits inside the central 66% safe circle.
    s = 512
    fg = svg(s, ship_layer(s, 1.06, 254, 256))
    bg = svg(s, backdrop(s) + vignette(s))
    mono = svg(s, ship_layer(s, 1.06, 254, 256, mono=True))
    render(fg, 432).save(os.path.join(OUT, "android_fg_432.png"))
    render(bg, 432).save(os.path.join(OUT, "android_bg_432.png"))
    render(mono, 432).save(os.path.join(OUT, "android_mono_432.png"))

    # Windows .ico: small sizes come from the square art so corners stay crisp.
    big = render(rounded, 256)
    big.save(os.path.join(OUT, "icon.ico"),
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("icon written to", OUT)


if __name__ == "__main__":
    main()
