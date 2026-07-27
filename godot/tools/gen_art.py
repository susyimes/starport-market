#!/usr/bin/env python3
"""Starport Market v3 — procedural pixel-art generator ("Dockline Neon").

All sprites are hand-authored pixel maps (one char = one pixel) rendered with
a shared neon palette; the stall and background are composed with pixel-exact
helpers (bayer dithering, auto outline, quantized glow).  Craft rules follow
docs/redesign-v3-spec.md section 2: 1px #0D0F1A outline, three-step shading
with the key light top-left, readable silhouettes, no random confetti noise.

    python tools/gen_art.py            # writes PNGs into assets/
    python tools/gen_art.py --preview  # also writes contact sheets to .preview/gen/
"""
from __future__ import annotations

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ICON = os.path.join(ROOT, "assets", "icons")
OUT_CHAR = os.path.join(ROOT, "assets", "characters")
OUT_BG = os.path.join(ROOT, "assets", "backgrounds")
OUT_UI = os.path.join(ROOT, "assets", "ui")
PREVIEW = os.path.join(ROOT, ".preview", "gen")

# ─── palette ─────────────────────────────────────────────────────────────────
# Every hue is a 3-step ramp: UPPER = light, lower = base, digit/symbol = dark.
PAL: dict[str, tuple[int, int, int, int]] = {
    ".": (0, 0, 0, 0),
    "K": (13, 15, 26, 255),       # unified outline
    "k": (24, 27, 46, 255),       # near-black fill / inner line
    "W": (245, 247, 255, 255),    # white ramp
    "w": (204, 210, 234, 255),
    "0": (148, 155, 186, 255),
    "S": (164, 174, 202, 255),    # steel ramp
    "s": (110, 119, 150, 255),
    "1": (70, 77, 106, 255),
    "N": (60, 67, 100, 255),      # navy-cloth ramp
    "n": (40, 45, 72, 255),
    "2": (28, 32, 52, 255),
    "L": (184, 255, 61, 255),     # lime ramp
    "l": (128, 194, 42, 255),
    "3": (82, 134, 30, 255),
    "V": (154, 123, 255, 255),    # violet ramp
    "v": (110, 82, 205, 255),
    "4": (74, 54, 145, 255),
    "G": (255, 209, 102, 255),    # gold ramp
    "g": (214, 156, 62, 255),
    "5": (156, 106, 44, 255),
    "M": (61, 255, 168, 255),     # mint ramp
    "m": (42, 188, 124, 255),
    "6": (28, 128, 88, 255),
    "R": (255, 77, 109, 255),     # red ramp
    "r": (196, 47, 80, 255),
    "7": (136, 30, 58, 255),
    "C": (77, 227, 255, 255),     # cyan ramp
    "c": (45, 164, 205, 255),
    "8": (30, 110, 148, 255),
    "P": (255, 110, 231, 255),    # magenta ramp
    "p": (196, 68, 178, 255),
    "9": (138, 44, 128, 255),
    "O": (255, 158, 77, 255),     # orange ramp
    "o": (206, 108, 46, 255),
    "f": (148, 72, 32, 255),
    "B": (198, 138, 86, 255),     # wood / bun ramp
    "b": (150, 98, 56, 255),
    "j": (102, 64, 36, 255),
    "T": (241, 197, 153, 255),    # tan skin ramp
    "t": (206, 152, 110, 255),
    "u": (160, 108, 74, 255),
    "A": (208, 180, 255, 255),    # lavender skin ramp
    "a": (166, 132, 232, 255),
    "@": (124, 92, 190, 255),
    "D": (201, 204, 232, 255),    # platinum cape ramp (luxe)
    "d": (152, 156, 196, 255),
    "*": (255, 255, 255, 255),    # sparkle core
    # translucent fx (alpha < 255 → never touched by auto-outline)
    "_": (13, 15, 26, 100),       # contact shadow
    "'": (184, 255, 61, 110),     # lime glow
    '"': (77, 227, 255, 110),     # cyan glow
    "^": (255, 209, 102, 110),    # warm glow
    "!": (255, 110, 231, 110),    # magenta glow
    "?": (154, 123, 255, 110),    # violet glow
    "~": (245, 247, 255, 150),    # glass shine / steam
    "=": (140, 225, 255, 70),     # glass pane
    ",": (245, 247, 255, 70),     # faint steam tail
}

OUTLINE = PAL["K"][:3]


def parse(rows: list[str]) -> Image.Image:
    """Char map → RGBA image (1 px per char)."""
    w = len(rows[0])
    for i, r in enumerate(rows):
        if len(r) != w:
            raise ValueError(f"ragged row {i} ({len(r)} vs {w}): {r!r}")
    img = Image.new("RGBA", (w, len(rows)))
    p = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch not in PAL:
                raise ValueError(f"unknown palette char {ch!r} at {x},{y}")
            p[x, y] = PAL[ch]
    return img


def outlined(img: Image.Image) -> Image.Image:
    """Add 1px #0D0F1A outline around every fully-opaque colored pixel.

    Transparent pixels that touch (4-neighbourhood) a colored opaque pixel
    become outline.  Authored K pixels do not propagate, translucent fx
    pixels are left alone — glows stay outline-free.
    """
    w, h = img.size
    src = img.load()
    out = img.copy()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    c = src[nx, ny]
                    if c[3] == 255 and c[:3] != OUTLINE:
                        dst[x, y] = PAL["K"]
                        break
    return out


def upscale(img: Image.Image, scale: int) -> Image.Image:
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def save(img: Image.Image, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print("gen", os.path.relpath(path, ROOT), img.size)


# low-level paint helpers for composed art (stall / background) ---------------

def px(img: Image.Image, x: int, y: int, c) -> None:
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), PAL[c] if isinstance(c, str) else c)


def rect(img: Image.Image, x0: int, y0: int, x1: int, y1: int, c) -> None:
    col = PAL[c] if isinstance(c, str) else c
    ImageDraw.Draw(img).rectangle([x0, y0, x1, y1], fill=col)


def hline(img: Image.Image, x0: int, x1: int, y: int, c) -> None:
    rect(img, x0, y, x1, y, c)


def vline(img: Image.Image, x: int, y0: int, y1: int, c) -> None:
    rect(img, x, y0, x, y1, c)


BAYER2 = ((0.25, 0.75), (1.0, 0.5))  # 2x2 ordered-dither thresholds
BAYER4 = tuple(tuple((v + 0.5) / 16.0 for v in row) for row in
               ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5)))


def dither_vgradient(img: Image.Image, y0: int, y1: int, stops: list[tuple]) -> None:
    """Vertical gradient across color stops: flat band interiors, bayer only in
    the narrow seam between bands (frac 0.3-0.7) so the sky never turns into a
    full-screen mesh of noise."""
    n = len(stops) - 1
    p = img.load()
    for y in range(y0, y1 + 1):
        t = (y - y0) / max(1, (y1 - y0)) * n
        i = min(int(t), n - 1)
        frac = t - i
        ca, cb = stops[i], stops[i + 1]
        if frac < 0.3:
            for x in range(img.width):
                p[x, y] = ca
        elif frac > 0.7:
            for x in range(img.width):
                p[x, y] = cb
        else:
            tt = (frac - 0.3) / 0.4
            for x in range(img.width):
                # deterministic per-pixel hash jitter (±0.08 on tt) breaks the
                # 4×4 tile alignment so band seams never resolve into rigid
                # full-width 2×2 checker stripes
                h = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
                h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
                jit = (((h >> 16) & 0xFF) / 255.0 - 0.5) * 0.16
                p[x, y] = cb if tt + jit > BAYER4[y % 4][x % 4] else ca
    return


def blend_px(img: Image.Image, x: int, y: int, col: tuple, alpha: float) -> None:
    if not (0 <= x < img.width and 0 <= y < img.height):
        return
    r, g, b = img.getpixel((x, y))[:3]
    a = max(0.0, min(1.0, alpha))
    img.putpixel((x, y), (int(r + (col[0] - r) * a),
                          int(g + (col[1] - g) * a),
                          int(b + (col[2] - b) * a)))


# ─── char-grid compositor (icons) ────────────────────────────────────────────

def grid(w: int = 24, h: int = 24) -> list[list[str]]:
    return [["."] * w for _ in range(h)]


def gput(g: list[list[str]], x: int, y: int, ch: str) -> None:
    if 0 <= y < len(g) and 0 <= x < len(g[0]):
        g[y][x] = ch


def stamp(g: list[list[str]], rows: list[str], ox: int, oy: int) -> None:
    for dy, row in enumerate(rows):
        for dx, ch in enumerate(row):
            if ch != ".":
                gput(g, ox + dx, oy + dy, ch)


def rows_of(g: list[list[str]]) -> list[str]:
    return ["".join(r) for r in g]


def shade3(dxn: float, dyn: float) -> int:
    """0=light 1=base 2=dark for a sphere-ish surface, key light top-left."""
    t = dxn * 0.65 + dyn * 0.75
    if t < -0.42:
        return 0
    if t > 0.52:
        return 2
    return 1


# ─── icons 24×24 ─────────────────────────────────────────────────────────────

MEAT_CUBE = [
    "..WPPR..",
    ".WPRRRr.",
    "WPRRRRr7",
    "PRRRRrr7",
    "PRRRRrr7",
    "RRRrrr77",
    ".Rrrr77.",
    "..r777..",
]


def icon_neon_skewer() -> list[str]:
    g = grid()
    for i in range(20):                      # 2px bamboo stick, lower-left → upper-right
        x, y = 3 + i, 20 - i
        gput(g, x, y, "b")
        gput(g, x, y - 1, "B")
    gput(g, 23, 0, "w")                      # sharpened tip
    stamp(g, MEAT_CUBE, 2, 13)               # three glazed chunks, corner-welded chain
    stamp(g, MEAT_CUBE, 8, 7)
    stamp(g, MEAT_CUBE, 14, 1)
    gput(g, 2, 21, "G"); gput(g, 3, 21, "G")  # handle knob
    gput(g, 2, 22, "g"); gput(g, 3, 22, "g")
    for dx, dy, ch in ((0, 0, "W"), (-1, 0, "w"), (1, 0, "w"), (0, -1, "w"), (0, 1, "w")):
        gput(g, 12 + dx, 4 + dy, ch)         # starlight cross hugging the top chunk
    shadow(g, 1, 10, 23)
    return rows_of(g)


DONUT_DRIP = [0, 1, 1, 2, 3, 2, 1, 2, 4, 3, 1, 1, 2, 3, 2, 4, 2, 1, 3, 2, 1, 1, 0, 0]


def icon_star_donut() -> list[str]:
    g = grid()
    cx, cy, rx, ry = 11.5, 11.5, 9.6, 8.2
    hx, hy, hrx, hry = 11.5, 11.0, 3.4, 2.9
    frost = "Pp9"
    bun = "Bbj"
    for y in range(24):
        for x in range(24):
            dxn = (x - cx) / rx
            dyn = (y - cy) / ry
            q = dxn * dxn + dyn * dyn
            if q > 1.0:
                continue
            hdx = (x - hx) / hrx
            hdy = (y - hy) / hry
            hq = hdx * hdx + hdy * hdy
            if hq < 1.0:
                continue
            s = shade3(dxn, dyn)
            if q > 0.80 and (dxn + dyn) > 0.15:
                s = 2                        # outer rim, shadow side
            if hq < 1.9 and hdy < 0.2:
                s = min(2, s + 1)            # inner-hole shadow
            icing = y < cy + DONUT_DRIP[x] - 1
            g[y][x] = (frost if icing else bun)[s]
    for x, y in ((9, 4), (10, 4), (11, 4)):
        gput(g, x, y, "P")
    gput(g, 8, 5, "W"); gput(g, 9, 5, "W")            # icing highlight
    gput(g, 7, 6, "G"); gput(g, 6, 7, "G"); gput(g, 8, 7, "W")   # gold star sprinkle
    gput(g, 7, 8, "G"); gput(g, 7, 7, "G")
    gput(g, 14, 5, "L"); gput(g, 15, 5, "L")          # sprinkles, deliberate
    gput(g, 17, 8, "C"); gput(g, 17, 9, "C")
    gput(g, 4, 11, "C"); gput(g, 4, 12, "C")
    gput(g, 12, 13, "L"); gput(g, 18, 13, "W")
    for dx, dy, ch in ((0, 0, "W"), (-1, 0, "w"), (1, 0, "w"), (0, -1, "w"), (0, 1, "w")):
        gput(g, 20 + dx, 6 + dy, ch)                  # starlight cross on the glaze rim
    shadow(g, 4, 19, 21)
    return rows_of(g)


def icon_ion_soda() -> list[str]:
    rows = [
        "........................",
        "..............PP........",
        "..............PP........",
        ".............Pp.........",
        ".............Pp.........",
        "......wWWWWWWPWWw.......",
        "......SwwwwwwwwwS.......",
        "......SCCCCCCCCcS.......",
        "......SCWCCCCCCcS.......",
        "......SCCCCCCCCcS.......",
        "......SCCCCWCCCcS.......",
        "......SCCCCCCCCcS.......",
        "......SCCCCCCWCcS.......",
        "......SCcCCCCCCcS.......",
        ".......SCCCCCCcS........",
        ".......SCCWCCccS........",
        ".......SCcCCcccS........",
        ".......Scc8cc88S........",
        ".......S8888888S........",
        "........wsssssw.........",
        "........................",
        "........................",
        "........................",
        "........................",
    ]
    g = [list(r) for r in rows]
    for dx, dy, ch in ((0, 0, "W"), (-1, 0, "w"), (1, 0, "w"), (0, -1, "w"), (0, 1, "w")):
        gput(g, 4 + dx, 7 + dy, ch)                    # starlight cross beside the can
    shadow(g, 6, 17, 21)
    return rows_of(g)


def icon_void_jelly() -> list[str]:
    g = grid()
    cx, cy, rx, ry = 11.5, 19.0, 9.6, 15.2

    def zone(t: float) -> int:
        if t < -0.30:
            return 0
        if t > 0.30:
            return 2
        return 1

    ramp = "Vv4"
    for y in range(4, 20):                             # dome: three clean zones,
        for x in range(24):                            # light upper-left, base
            dxn = (x - cx) / rx                        # middle, dark lower-right
            dyn = (y - cy) / ry
            q = dxn * dxn + dyn * dyn
            if q > 1.0:
                continue
            t = dxn * 0.65 + (dyn + 0.52) * 1.1
            z = zone(t)
            if z != zone(t - 0.07) and (x + y) % 2:
                z -= 1                                 # 1px interleaved zone seam
            ch = ramp[z]
            if q > 0.86 and dxn > 0.45:
                ch = "M"                               # mint rim light, right edge
            g[y][x] = ch
    for yy in range(8, 15):                            # trapped star: 3x3 W core,
        for xx in range(8, 15):                        # gold ring, 1px dark halo
            ddx, ddy = xx - 11, yy - 11
            d = max(abs(ddx), abs(ddy))
            if d <= 1:
                g[yy][xx] = "W"
            elif d == 2:
                g[yy][xx] = "4" if abs(ddx) == 2 and abs(ddy) == 2 else "G"
            elif d == 3 and abs(ddx) + abs(ddy) <= 4:
                g[yy][xx] = "4"
    for i in range(4):                                 # 2×4 diagonal glass shine —
        for sx in (5 + i, 6 + i):                      # opaque lavender light step,
            if g[9 - i][sx] in "Vv4":                  # clamped inside the dome
                g[9 - i][sx] = "A"
    for x in range(2, 22):                             # serving dish
        g[20][x] = "w" if 3 <= x <= 19 else "0"
    gput(g, 2, 21, "0"); gput(g, 21, 21, "0")
    for dx, dy, ch in ((0, 0, "W"), (-1, 0, "w"), (1, 0, "w"), (0, -1, "w"), (0, 1, "w")):
        gput(g, 16 + dx, 5 + dy, ch)                   # starlight cross on the crown edge
    shadow(g, 2, 21, 22)
    return rows_of(g)


def shadow(g: list[list[str]], x0: int, x1: int, y: int) -> None:
    for x in range(x0, x1 + 1):
        if g[y][x] == ".":
            g[y][x] = "_"


POP_CLUSTER = [
    "..WW.....WW...",
    ".WWWWw.wWWWWw.",
    "WWwWWWWWWWwWWw",
    "wWWWW0WWWWWWww",
    ".wWwWWWWw0WWw.",
]


def icon_meteor_popcorn() -> list[str]:
    g = grid()
    for y in range(8, 21):                   # tapered striped box
        hw = 7.0 - (y - 8) * 1.6 / 12.0
        x0 = int(11.5 - hw + 0.5)
        x1 = int(11.5 + hw + 0.5)
        for x in range(x0, x1 + 1):
            stripe = ((x - x0) // 3) % 2
            ch = "R" if stripe == 0 else "W"
            if x > x1 - 2 or y > 18:
                ch = "r" if stripe == 0 else "w"
            if x == x0:
                ch = "R" if stripe == 0 else "W"
            g[y][x] = ch
    for x in range(5, 19):                   # box rim
        if g[8][x] != ".":
            g[8][x] = "k" if 6 < x < 17 else g[8][x]
    stamp(g, POP_CLUSTER, 5, 4)              # overflowing popcorn
    gput(g, 16, 3, "W"); gput(g, 17, 3, "w")  # escape kernel fused to the heap crest
    gput(g, 18, 2, "C"); gput(g, 19, 1, "C")  # 2px meteor tail off the crest
    shadow(g, 5, 18, 22)
    return rows_of(g)


def icon_holo_sticker() -> list[str]:
    g = grid()
    x0, y0, x1, y1 = 3, 3, 20, 20
    bands = "cpv"                            # three wide muted bands (base tones)
    lit = {"c": "C", "p": "P", "v": "V"}
    dark = {"c": "8", "p": "9", "v": "4"}
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if (x in (x0, x1) and y in (y0, y1)):
                continue                     # rounded corners
            s = x + y
            if s >= 31:
                continue                     # peeled corner cut (bigger tear)
            i = min(2, max(0, (s - 6) // 8))
            ch = bands[i]
            if s <= 8:                       # key light only on the 2-3px edge
                ch = lit[ch]
            if s == 30:                      # crease line along the peel
                ch = dark[ch]
            g[y][x] = ch
    for x in range(x0 + 1, x1):              # die-cut bright inner edge on rim
        if x + y0 < 30:
            g[y0][x] = "w"
        if x + y1 < 30:
            g[y1][x] = "w"
    for y in range(y0 + 1, y1):
        if x0 + y < 30:
            g[y][x0] = "w"
        if x1 + y < 30:
            g[y][x1] = "w"
    for x in range(14, 18):                  # curled backing: white/grey two-step
        gput(g, x, 31 - x, "W")
        gput(g, x, 32 - x, "0")
    gput(g, 15, 18, "9"); gput(g, 16, 17, "9"); gput(g, 17, 16, "9")  # dark fold
    gput(g, 15, 19, "_"); gput(g, 16, 18, "_"); gput(g, 17, 17, "_")  # curl shadow
    stamp(g, ["....L....",
              "....L....",
              "...LLL...",
              "..LWWWL..",
              "LLWWWWWLL",
              "..LWWWL..",
              "...LLL...",
              "....L....",
              "....L...."], 7, 6)            # enlarged four-point star emblem
    for x, y, ch in ((5, 5, "C"), (6, 4, "C"), (7, 3, "W")):
        gput(g, x, y, ch)                    # holo sheen: opaque band-light steps
    for dx, dy, ch in ((0, 0, "W"), (-1, 0, "w"), (1, 0, "w"), (0, -1, "w"), (0, 1, "w")):
        gput(g, 21 + dx, 5 + dy, ch)         # starlight cross on the die-cut edge
    shadow(g, 4, 19, 22)
    return rows_of(g)


def icon_orbit_plush() -> list[str]:
    g = grid()
    cx, cy, r = 11.5, 10.5, 8.3
    ramp = "Mm6"
    for y in range(24):
        for x in range(24):
            dxn = (x - cx) / r
            dyn = (y - cy) / r
            if dxn * dxn + dyn * dyn > 1.0:
                continue
            g[y][x] = ramp[shade3(dxn, dyn)]
    rcx, rcy, rrx, rry = 11.5, 13.5, 11.3, 3.1
    for y in range(24):                      # planetary ring, back pass then front
        for x in range(24):
            dxn = (x - rcx) / rrx
            dyn = (y - rcy) / rry
            q = dxn * dxn + dyn * dyn
            if not (0.62 <= q <= 1.08):
                continue
            sx = (x - cx) / r
            sy = (y - cy) / r
            on_sphere = sx * sx + sy * sy <= 1.0
            if y < rcy and on_sphere:
                continue                     # back half hidden by plush
            ch = "G" if x < cx - 2 else ("g" if x < cx + 5 else "5")
            if q > 0.95 and y >= rcy:
                ch = "5"
            g[y][x] = ch
    gput(g, 9, 2, "M"); gput(g, 8, 3, "M"); gput(g, 9, 3, "m")   # ear tuft
    for ex in (8, 13):                       # button eyes + glint
        gput(g, ex, 8, "K"); gput(g, ex + 1, 8, "K")
        gput(g, ex, 9, "K"); gput(g, ex + 1, 9, "K")
        gput(g, ex, 8, "*")
    gput(g, 11, 11, "k"); gput(g, 12, 11, "k")                   # stitched smile
    gput(g, 10, 10, "k"); gput(g, 13, 10, "k")
    gput(g, 7, 11, "P"); gput(g, 16, 11, "P")                    # blush
    gput(g, 15, 5, "k"); gput(g, 16, 6, "k")                     # seam stitches
    for dx, dy, ch in ((0, 0, "W"), (-1, 0, "w"), (1, 0, "w"), (0, -1, "w"), (0, 1, "w")):
        gput(g, 8 + dx, 1 + dy, ch)                              # starlight by the ear
    shadow(g, 4, 19, 21)
    return rows_of(g)


def icon_quantum_coffee() -> list[str]:
    # cylinder three-step: 2px lit left column, base middle, 2-3px shadow right
    # with the light/dark boundary at ~2/3 of the cup width; the boundary column
    # is toothed row-to-row and tucks inward at band tops/bottoms to curve the
    # surface; steam is one continuous 2px S-curl rooted on the lid vent
    rows = [
        "............~,..........",
        "............~~..........",
        "..........,~~...........",
        ".........~~,............",
        ".........~~.............",
        "..........~,............",
        "......WWwwww00..........",
        "......WWwwwww000........",
        "......w000000000........",
        "......WWwwwww000........",
        "......WWwwwwww00........",
        "......WWwwwww000........",
        "......VVvvvvv444........",
        "......VVvvvvvv44........",
        "......VVvLLLl444........",
        "......VVLvCCvl44........",
        "......VVvLLLl444........",
        "......VVvvvvvv44........",
        "......vVvvvvv444........",
        ".......WWwww000.........",
        ".......WWwwww00.........",
        "........wwww00..........",
        "........................",
        "........................",
    ]
    g = [list(r) for r in rows]
    for dx, dy, ch in ((0, 0, "W"), (-1, 0, "w"), (1, 0, "w"), (0, -1, "w"), (0, 1, "w")):
        gput(g, 15 + dx, 6 + dy, ch)         # starlight cross on the lid rim
    shadow(g, 7, 16, 22)
    return rows_of(g)


ICONS = {
    "neon_skewer": icon_neon_skewer,
    "star_donut": icon_star_donut,
    "ion_soda": icon_ion_soda,
    "void_jelly": icon_void_jelly,
    "meteor_popcorn": icon_meteor_popcorn,
    "holo_sticker": icon_holo_sticker,
    "orbit_plush": icon_orbit_plush,
    "quantum_coffee": icon_quantum_coffee,
}

PRODUCT_ORDER = [
    "neon_skewer", "star_donut", "ion_soda", "void_jelly",
    "meteor_popcorn", "holo_sticker", "orbit_plush", "quantum_coffee",
]

ICON_SIZE = 24


def build_icon(pid: str) -> Image.Image:
    rows = ICONS[pid]()
    if len(rows) != ICON_SIZE or len(rows[0]) != ICON_SIZE:
        raise ValueError(f"icon {pid} is {len(rows[0])}x{len(rows)}, want 24x24")
    return outlined(parse(rows))


def gen_icons() -> None:
    for pid in PRODUCT_ORDER:
        save(upscale(build_icon(pid), 10), os.path.join(OUT_ICON, f"product_{pid}.png"))


# ─── characters 32×44 (hand-authored maps) ───────────────────────────────────

CHAR_W, CHAR_H = 32, 44

CHAR_DOCK = [
    "................................",
    "................................",
    "............GGGGGGGG............",
    "...........GGGGGGGGgg...........",
    "..........GGGGWCWGGGgC..........",
    "..........GGGGgCgGGGgC..........",
    "..........gggggggggggg..........",
    "........GGGGGGGGGGGGGGgg........",
    "...........TTTTTTTTtt...........",
    "...........TTkTTTTkTt...........",
    "...........TTWKTTWKTt...........",
    "...........TTKKTTKKTt...........",
    "...........TtTTTTTTtt...........",
    "...........TTTuuuuTTt...........",
    "...........tTTTTTTttu...........",
    "........OOOOOOttttOOOOoo........",
    "......NNnOOLLOokOOoLLOfnnP......",
    "......NNnOOLLOokOOoLLOfnnP......",
    "......NNnOOLLOokOOoLLOfnnP......",
    "......NNnoOllofkOoollofnnP......",
    "......NNnOOLLOokOOoLLOfnnP......",
    "......NNnOOLLOokOOoLLOfnnP......",
    "......NNnoOllofkOoollofnnP......",
    "......NNnOOLLOokOOoLLOfnnP......",
    "......NNnoo33ofkooo33ofnnP......",
    "......gggNNNNNNNNNNNNnnggg......",
    "......gggNNNNNNNNNNNNnnggg......",
    ".........jjjjjjGGjjjjjj.........",
    "..........Nnnnnnnnnnn2..........",
    "..........Nnnnnnnnnnn2..........",
    "..........Nnnnn..nnnn2..........",
    "..........Nnnnn..nnnn2..........",
    "..........Nnnnn..nnnn2..........",
    "..........Nnnnn..nnnn2..........",
    "..........Nnnnn..nnnn2..........",
    "..........Nnnnn..nnnn2..........",
    "..........Nnnnn..nnnn2..........",
    ".........bbbbbb..bbbbbb.........",
    ".........Bbbbbj..Bbbbbj.........",
    ".........Bbbbbj..Bbbbbj.........",
    ".........jjjjjj..jjjjjj.........",
    "................................",
    "......._________________........",
    "................................",
]

CHAR_PILOT = [
    "................................",
    "............WWWWWWww............",
    "...........WCCWCCCCcw...........",
    "..........WCCCWWCCCCcw..........",
    "..........WCWCCWWCCCcw..........",
    "..........wCCWCCWWCCcw..........",
    "..........wCcCCCCWWCcw..........",
    "..........wccCCCCCWCcw..........",
    "..........wcc8888888cw..........",
    "...........wwwwwwwwsw...........",
    "..............tttt..............",
    "...........SSSSSSSSss...........",
    ".......OOOWWWWWWWWWWwsOOo.......",
    ".......OOOWWWWWWWWWWwsOOo.......",
    ".......WWwWWWWWkWWWwwws11.......",
    ".......WWwWWWWWkWWWwwws11.......",
    ".......WWwWWWkkkkkkWwws11.......",
    ".......WWwWWWkCGLRkWwws11.......",
    ".......WWwWWWk8g3rkWwws11.......",
    ".......WWwWWWkkkkkkWwws11.......",
    ".......WWwWWWWWkWWWwwws11.......",
    ".......WWwWWWWWkWWWwwws11.......",
    ".......OOoWWWWWkWWWwwsOOo.......",
    ".......wwsWWWWWkWWWwwwss1.......",
    ".......sssssssSSssssss111.......",
    "..........WWWWWWWWwwss..........",
    "...........WWws..wss1...........",
    "...........WWws..wss1...........",
    "...........WWws..wss1...........",
    "...........WWws..wss1...........",
    "...........WWws..wss1...........",
    "...........OOOo..Ooof...........",
    "...........OOOo..Ooof...........",
    "...........WWws..wss1...........",
    "...........WWws..wss1...........",
    "...........WWws..wss1...........",
    "..........SSSSs..Sssss..........",
    "..........SSSSs..Sssss..........",
    "..........SSSSs..Sssss..........",
    "..........sssss..ssss1..........",
    "..........11111..11111..........",
    "................................",
    "........________________........",
    "................................",
]

CHAR_TOURIST = [
    "................................",
    "...........GG......GG...........",
    "...........Gg......Gg...........",
    "............m......m............",
    "............m......m............",
    "..........GGGGGGGGGGgg..........",
    "..........GGGGGGGGGGgg..........",
    "..........RRRRRRRRRRrr..........",
    "....GGGGGGGGGGGGGGGGGGGGGGgC....",
    "......gggggggggggggggggggg......",
    "...........MMMMMMMMmm...........",
    "...........MWKKMMWKKm...........",
    "...........MWKKMMWKKm...........",
    "...........MKKKMMKKKm...........",
    "...........MmMuuuuMmm...........",
    "...........mMMMMMMMmm...........",
    "..............mmmm..............",
    "........PPPPPPMMMMPPPPpp........",
    "......PPPPPWPPPPPPPPWPpPpp......",
    "......PPPPPkPPPPPPkPPpPpp.......",
    "......PPPPLPPkPPPPkPPLpPpp......",
    "......PPPPPPPsssssGPPppPpp......",
    "......MMmPPPPkkCCkkPPppMmm......",
    "......MMmPPPPkkkkkkPPppMmm......",
    "......MMmppPPPPPPPPPpppMmm......",
    "..........nnnnnnnnnnnn..........",
    "..........nnnnnnnnnnnn..........",
    "..........nnnnnnnnnn22..........",
    "...........MMmm..Mmmm...........",
    "...........MMmm..Mmmm...........",
    "...........MMmm..Mmmm...........",
    "...........MMmm..Mmmm...........",
    "...........MMmm..Mmmm...........",
    "...........MMmm..Mmmm...........",
    "...........MMmm..Mmmm...........",
    "...........MMmm..Mmmm...........",
    "...........MMmm..Mmmm...........",
    "...........MMmm..Mmmm...........",
    "..........bbbbb..bbbbb..........",
    "..........Bbbbj..Bbbbj..........",
    "..........jjjjj..jjjjj..........",
    "................................",
    "......____________________......",
    "................................",
]

CHAR_MONK = [
    "................................",
    "................................",
    "...............G................",
    ".............VVVvvv.............",
    "...........VVVVvvvvvv...........",
    "..........VVVVvvvvvvvc..........",
    "..........VVVVvvvvvvvc..........",
    "..........VVVVvvvvvvvc..........",
    "..........VVkkkkkkkkvv..........",
    "..........Vkkkkkkkkkkv..........",
    "..........VkkCCkkCCkkv..........",
    "..........VkkCCkkCCkkv..........",
    "..........Vkkkkkkkkkkv..........",
    "..........Vvkkkkkkkkvv..........",
    ".........VVVvvvvvvv4444...B.....",
    "........VVVVvvvvvvv44444..B.....",
    "........VVVGvvvvvvv4G444vvB.....",
    "........VVVVGvvvvvvG4444vvB.....",
    "........VVVVvvGvvGv44444vvB.....",
    "........VVVVvvvvvvv44444..B.....",
    "........VVVVv4vv4vv44444..B.....",
    "........VVVVv4vv4vv44444..B.....",
    "........VVVVv4vv4vv44444..B.....",
    "........VVVVv4vv4vv44444.^k^....",
    "........VVVVv4vv4vv44444.k5k^...",
    "........VVVVv4vv4vv444445WWG5^..",
    "........VVVVv4vv4vv444445WGG5^..",
    "........VVVVv4vv4vv44444.k5k^...",
    "........VVVVv4vv4vv44444.^^^....",
    "........VVVVv4vv4vv44444........",
    "........VVVVv4vv4vv44444........",
    "........VVVVv4vv4vv44444........",
    ".......VVVVVv4vv4vvv44444.......",
    ".......VVVVVv4vv4vvv44444.......",
    ".......VVVVVv4vv4vvv44444.......",
    ".......VVVVVv4vv4vvv44444.......",
    "......VVVVVVv4vv4vvvv44444......",
    "......VVVVVVv4vv4vvvv44444......",
    "......VVVVVVv4vv4vvvv44444......",
    "......vvvvvvv4vv4vvvv44444......",
    "......44444444444444444444......",
    "................................",
    "......____________________......",
    "................................",
]

CHAR_SCRAP = [
    "................................",
    "................................",
    "................................",
    "............NNnnnnnn............",
    "...........NNNnnnnnnn...........",
    "..........NNNnnnnnnnnn..........",
    "..........kCCCkkCCCkkk..........",
    "..........kccckkccckkk..........",
    "...........TTTTTTTTtt...........",
    "...........TkTTTTkTTt...........",
    "...........TWKTTTWKTt...........",
    "...........TKKTTTKKTt...........",
    "...........TtTTTTTTtt...........",
    "...........TTTuuuTTTt...........",
    "..........RRRRRRRRRrrr..........",
    "..S.BBbj..RRRRRRRRRrrr..........",
    "..SSBBbbj.ssRrsssnn22o..........",
    "...sSBbbj.ssRrssnnn22oP.........",
    "...sSBbjj.sNNOOonCC22oP.........",
    "....sBbbj.sNkOookCC22oP.........",
    "....1Bjjj.sNnooonnn22oP.........",
    "....sBbbj.sNnnknBBb22oP.........",
    "....sBbbj.snnnnkBbb22oP.........",
    "....1bbjj.snnnnnbbb22o..........",
    ".....bjj..snnnnnnkn22o..........",
    "..........ggnnnnnnngg2..........",
    "..........jjjjjjjjjjj2..........",
    "..........Ssssssssss11..........",
    "..........Sssss..ssss1..........",
    "..........Sssss..ssss1..........",
    "..........Sssss..ssss1..........",
    "..........Sssss..ssss1..........",
    "..........Sssss..ssss1..........",
    "..........Sssss..ssss1..........",
    "..........Sssss..ssss1..........",
    "..........Sssss..ssss1..........",
    ".........jjjjjj..jjjjjj.........",
    ".........jjjjjj..jjjjjj.........",
    ".........Sjjjjj..Sjjjjj.........",
    ".........Sjjjjj..Sjjjjj.........",
    ".........222222..222222.........",
    "................................",
    "...._______________________.....",
    "................................",
]

CHAR_LUXE = [
    "................................",
    "............WWAaaaaa@...........",
    "...........AAAaaaaa@@@..........",
    "..........AAAAaaaaa@@@..........",
    "..........AAAAaaaaa@@@@.........",
    "..........AAAaaaaaa@@@@.........",
    "..........Aaa@@@@@@@@@..........",
    "...........AAAAAAAAaa...........",
    "...........AkAAAAkAaa...........",
    "...........AAAAAGGGAa...........",
    "...........AWKAAGCGAa...........",
    "...........AKKAAGGGAa...........",
    "...........AAAAAAGAAa...........",
    "...........AAA@@AAGAa...........",
    "...........aAAAAAAAG@...........",
    "..........WWWWWWWWWWww..........",
    "...DDWWWWWWWWWWWWWWWWWWwwwdd2...",
    "....DDDddWWGGWWWWGGWWwwdd22P....",
    ".....DDddWGGGGGGGGGGGGwdd22P....",
    ".....DDddWWGGGGGGGGGGwwdd22P....",
    ".....DDGgWWWWWWkWWWWWwwgG22P....",
    ".....DDGgWWWGWWkWWGWWwwgG22P....",
    ".....DDGgWWWWWWkWWWWWwwgG22P....",
    ".....DDGgWWWGWWkWWGWWwwgG22P....",
    ".....DDGgWWWWWWkWWWWWwwgG22P....",
    ".....DDGggggggggggggggggG22P....",
    "....DDddGg2WWww22Wwww2gGdd2P....",
    "....DDddGg2WWww22Wwww2gGdd22P...",
    "....DDddGg2WWww22Wwww2gGdd22P...",
    "....DdddGg2wWww22Wwwwd2gGd22P...",
    "....DDddGg2WWww22Wwww2gGdd22P...",
    "....DDddGg2WWww22Wwww2gGdd22P...",
    "....DDddGg2WWww22Wwww2gGdd22P...",
    "....DdddGg2wWww22Wwwwd2gGd22P...",
    "...DDDddGg2WWww22Wwww2gGdd22P...",
    "...DDDddGg2WWww22Wwww2gGdd2P....",
    "...DDdddGg2WWww22Wwww2gGd22P....",
    "...DDdd2Gg2GWww22Gwww2gG222P....",
    "...Ddd22Gg2GWww22Gwww2gG222P....",
    "..........GWwww..GWwww..........",
    "..........sssss..sssss..........",
    "................................",
    ".....______________________.....",
    "................................",
]

CHAR_VENDOR = [
    "....................LL..........",
    "....................LL..........",
    "....................s...........",
    "....................s...........",
    ".......SSSSSSSSSSSSSSSSss.......",
    ".......SSkkkkkkkkkkkkkkss.......",
    ".......SSk~~kkkkkkkkkkkss.......",
    ".......SSkkkLLkkkkLLkkkss.......",
    "......sSSkkkLLkkkkLLkkksss......",
    "......sSS8k8Lk8k8k8Lk8ksss......",
    ".......SSkkkkLLLLLLkkkkss.......",
    ".......SSk8k8k8k8k8k8k8ss.......",
    ".......SSkkkkkkkkkkkkkkss.WWW...",
    ".......Sssssssssssssssss1.WWW...",
    ".......Sssssssssssssss111SSs....",
    "..............ssss.......SSs....",
    "........SSSSSSSSSSSSSSsssS......",
    ".....ss.SSGGGGGGGGGGGGSs.ss.....",
    ".....ss.SSGGGGGGGGGGGGSs.ss.....",
    ".....ss.SSGGGGGGGGGGGGSs.ss.....",
    ".....ss.SSGGGGLLGGGGGGSs.ss.....",
    ".....ss.SSGGGGLLGGGGGGSs.ss.....",
    ".....ss.SSGGgggggggGGGSs.ss.....",
    ".....ss.SSGGg55555gGGGSs.ss.....",
    ".....11.SSGGgggggggGGGSs.11.....",
    "........SSggggggggggggSs........",
    "........SSggggggggggggSs........",
    "........SSssssssssssss1s........",
    "........Sssssssssssssss1........",
    ".........ssssssssssss11.........",
    "........1111111111111111........",
    "........1111111111111111........",
    "........11L11111111L1111........",
    "........1111111111111111........",
    "........SSsssssssssssss1........",
    "........1111111111111111........",
    "........kSSk..kSSk..kSSk........",
    "........kSsk..kSsk..kSsk........",
    "........ks1k..ks1k..ks1k........",
    "........k11k..k11k..k11k........",
    ".........kk....kk....kk.........",
    "................................",
    "......._________________........",
    "................................",
]

CHARACTERS = {
    "customer_dock": CHAR_DOCK,
    "customer_pilot": CHAR_PILOT,
    "customer_tourist": CHAR_TOURIST,
    "customer_monk": CHAR_MONK,
    "customer_scrap": CHAR_SCRAP,
    "customer_luxe": CHAR_LUXE,
    "vendor_m0x": CHAR_VENDOR,
}


def build_character(name: str) -> Image.Image:
    rows = CHARACTERS[name]
    if len(rows) != CHAR_H or any(len(r) != CHAR_W for r in rows):
        bad = [i for i, r in enumerate(rows) if len(r) != CHAR_W]
        raise ValueError(f"character {name}: bad rows {bad}")
    return outlined(parse(rows))


def gen_characters() -> None:
    for name in CHARACTERS:
        save(upscale(build_character(name), 10),
             os.path.join(OUT_CHAR, f"{name}.png"))


# ─── stall 128×80 ────────────────────────────────────────────────────────────

MINI: dict[str, list[str]] = {
    "neon_skewer": [
        "...b...",
        "..RRr..",
        "..RLr..",
        "...b...",
        "..RRr..",
        "..RLr..",
        "...b...",
        "...b...",
    ],
    "star_donut": [
        ".......",
        ".PPPp..",
        "PPPPPp.",
        "PP..Pp.",
        "Pp..pp.",
        "Bbpppb.",
        ".bbbb..",
        ".......",
    ],
    "ion_soda": [
        "..P....",
        ".wWWw..",
        ".wCCc..",
        ".wCCc..",
        ".wCcc..",
        ".wccc..",
        ".w88c..",
        ".SSSs..",
    ],
    "void_jelly": [
        ".......",
        ".VVVv..",
        "VVVVvv.",
        "VVGVvv.",
        "VVVVvv.",
        "Vvvvvv.",
        ".v44v..",
        ".......",
    ],
    "meteor_popcorn": [
        "..WWw..",
        ".WWwWw.",
        ".RWRWr.",
        ".RWRWr.",
        ".RWRWr.",
        ".rwrwr.",
        ".......",
        ".......",
    ],
    "holo_sticker": [
        ".......",
        ".CCm...",
        "CCMMp..",
        "CMMPp..",
        ".MPPp..",
        "..ppp..",
        ".......",
        ".......",
    ],
    "orbit_plush": [
        ".......",
        "..MMm..",
        ".MMMMm.",
        "GGMMmgg",
        ".MKMKm.",
        "..mmm..",
        ".......",
        ".......",
    ],
    "quantum_coffee": [
        ".......",
        ".wWWw..",
        ".VVVv..",
        ".VLVv..",
        ".VVVv..",
        ".wWWw..",
        ".......",
        ".......",
    ],
}


def draw_stall() -> Image.Image:
    im = Image.new("RGBA", (128, 80), (0, 0, 0, 0))
    fx = Image.new("RGBA", (128, 80), (0, 0, 0, 0))   # translucent overlay

    # back wall + vertical seams
    rect(im, 10, 24, 117, 58, "2")
    for sx in (26, 42, 58, 74, 90, 106):
        vline(im, sx, 26, 57, "k")
    hline(im, 10, 117, 58, "k")
    # warm lantern light washing down the wall (quantized + checkered)
    gold = PAL["G"][:3]
    tints = (0.26, 0.20, 0.14, 0.09, 0.05)
    for i, f in enumerate(tints):
        y = 24 + i
        for x in range(10, 118):
            ff = f * (0.55 if (i >= 2 and (x + y) % 2) else 1.0)
            if im.getpixel((x, y))[:3] == PAL["2"][:3]:
                base = PAL["2"]
                im.putpixel((x, y), (int(base[0] + (gold[0] - base[0]) * ff),
                                     int(base[1] + (gold[1] - base[1]) * ff),
                                     int(base[2] + (gold[2] - base[2]) * ff), 255))

    # shelf board + mini products
    hline(im, 12, 115, 39, "B")
    hline(im, 12, 115, 40, "b")
    hline(im, 12, 115, 41, "j")
    for bx_ in (20, 60, 100):
        vline(im, bx_, 42, 44, "j")
    slots = [20, 33, 45, 58, 70, 83, 95, 108]
    for i, pid in enumerate(PRODUCT_ORDER):
        mini = outlined(parse(MINI[pid]))
        im.paste(mini, (slots[i] - mini.width // 2, 39 - mini.height), mini)

    # wooden counter top
    rect(im, 8, 42, 119, 45, "b")
    hline(im, 8, 119, 42, "B")
    hline(im, 8, 119, 45, "j")
    for gx in range(14, 116, 17):
        hline(im, gx, gx + 3, 44, "j")

    # glass display case
    rect(im, 12, 46, 115, 64, "s")
    rect(im, 14, 48, 62, 62, "2")
    rect(im, 65, 48, 113, 62, "2")
    hline(im, 12, 115, 46, "S")
    vline(im, 12, 46, 64, "S"); vline(im, 13, 46, 64, "s")
    vline(im, 63, 47, 63, "S"); vline(im, 64, 47, 63, "s")
    vline(im, 114, 46, 64, "s"); vline(im, 115, 46, 64, "1")
    rect(im, 12, 63, 115, 64, "1")
    goods = [("star_donut", 20), ("ion_soda", 33), ("void_jelly", 46),
             ("meteor_popcorn", 71), ("holo_sticker", 84), ("neon_skewer", 97)]
    for pid, gx in goods:                      # mini recognizable stock, not blocks
        mini = outlined(parse(MINI[pid]))
        bbox = mini.getbbox()
        im.paste(mini, (gx, 62 - (bbox[3] - 1)), mini)      # rest on case floor
        rect(im, gx + 1, 63, gx + mini.width - 2, 63, "2")  # shelf contact shadow
    for x0, x1 in ((14, 62), (65, 113)):
        for x in range(x0, x1 + 1):
            for y in range(48, 63):
                r0, g0, b0, _ = im.getpixel((x, y))
                gc = PAL["="]
                a = gc[3] / 255.0
                im.putpixel((x, y), (int(r0 + (gc[0] - r0) * a),
                                     int(g0 + (gc[1] - g0) * a),
                                     int(b0 + (gc[2] - b0) * a), 255))
        for s0 in (10, 14):                    # diagonal shine
            for i in range(13):
                sxx = x0 + s0 + i
                syy = 61 - i
                if sxx <= x1 and 48 <= syy <= 62:
                    fx.putpixel((sxx, syy), (245, 247, 255, 90))

    # metal kick panel
    rect(im, 10, 65, 117, 71, "s")
    rect(im, 10, 70, 117, 71, "1")
    hline(im, 10, 117, 65, "S")
    for rx in range(16, 116, 12):
        px(im, rx, 67, "1"); px(im, rx, 69, "1")
    rect(im, 54, 65, 73, 70, "k")              # maker's badge lights
    ImageDraw.Draw(im).rounded_rectangle([54, 65, 73, 70], 2, outline=PAL["3"])
    for i, ch in enumerate(("L", "G", "L")):
        rect(im, 58 + i * 5, 67, 59 + i * 5, 68, ch)

    # side poles
    for px0 in (6, 120):
        vline(im, px0, 23, 71, "S")
        vline(im, px0 + 1, 23, 71, "s")
        rect(im, px0 - 1, 71, px0 + 2, 73, "1")
        hline(im, px0, px0 + 1, 23, "k")

    # awning: 45° diagonal stripes, three steps per stripe, dark scalloped hem
    for x in range(4, 124):
        for y in range(11, 20):
            ph = x - (y - 11)                  # constant along 45° diagonals
            stripe = (ph // 6) % 2
            light, base, dark = ("P", "p", "9") if stripe == 0 else ("V", "v", "4")
            pos = ph % 6
            ch = base
            if pos == 0:
                ch = light                     # lit upper-left edge of the stripe
            elif pos == 5:
                ch = dark                      # shaded lower-right edge
            if y >= 18:
                ch = dark                      # canopy underside rows in shade
            px(im, x, y, ch)
    hline(im, 4, 123, 10, "k")
    for sxx in range(4, 124, 6):               # scallops: hem pressed one step darker
        stripe = ((sxx - 9) // 6) % 2          # phase matches the diagonals at y=20
        dark = "9" if stripe == 0 else "4"
        hline(im, sxx, sxx + 5, 20, dark)
        hline(im, sxx + 1, sxx + 4, 21, dark)
        hline(im, sxx + 1, sxx + 4, 22, dark)
        hline(im, sxx + 2, sxx + 3, 23, dark)

    # neon sign above
    rect(im, 46, 1, 82, 8, "k")
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([46, 1, 82, 8], 2, outline=PAL["L"])
    hline(im, 50, 56, 4, "L"); hline(im, 59, 65, 4, "L"); hline(im, 68, 76, 4, "L")
    hline(im, 50, 55, 6, "P"); hline(im, 58, 64, 6, "P"); hline(im, 67, 75, 6, "P")
    px(im, 50, 9, "k"); px(im, 78, 9, "k")
    gd = ImageDraw.Draw(fx)
    gd.rounded_rectangle([44, -1, 84, 10], 3, outline=(184, 255, 61, 120), width=2)

    # hanging lanterns
    for lx in (18, 108):
        vline(im, lx + 2, 24, 26, "k")
        rect(im, lx, 27, lx + 5, 33, "g")
        rect(im, lx, 28, lx + 4, 32, "G")
        px(im, lx + 1, 29, "W"); px(im, lx + 1, 30, "W")
        vline(im, lx + 5, 28, 32, "5")
        hline(im, lx + 2, lx + 3, 34, "5")
        gd.ellipse([lx - 4, 24, lx + 9, 37], fill=(255, 209, 102, 46))

    # steam wisps above the counter
    for i, (wx, wy) in enumerate(((100, 42), (101, 41), (102, 40), (101, 39),
                                  (100, 38), (101, 37), (102, 36), (103, 35))):
        fx.putpixel((wx, wy), (245, 247, 255, 110 - i * 8))
    for i, (wx, wy) in enumerate(((88, 41), (89, 40), (88, 39), (87, 38), (88, 37))):
        fx.putpixel((wx, wy), (245, 247, 255, 90 - i * 10))

    # ground contact shadow
    sd = ImageDraw.Draw(fx)
    sd.ellipse([6, 71, 121, 78], fill=(13, 15, 26, 95))

    fx = fx.filter(ImageFilter.GaussianBlur(0.6))
    out = Image.alpha_composite(im, fx)
    return outlined(out)


def gen_stall() -> None:
    save(upscale(draw_stall(), 6), os.path.join(OUT_CHAR, "stall.png"))


# ─── background 480×270 → 1920×1080 ─────────────────────────────────────────

BG_W, BG_H = 480, 270
HORIZON = 205


def _stars(im: Image.Image, rng: random.Random) -> None:
    tiers = [
        (95, (92, 100, 140)),      # faint
        (46, (162, 172, 208)),     # mid
        (18, (236, 240, 255)),     # bright
    ]
    for count, col in tiers:
        for _ in range(count):
            x = rng.randrange(BG_W)
            y = rng.randrange(0, 185)
            if (x - 408) ** 2 + (y - 46) ** 2 < 52 ** 2:
                continue                       # keep the planet clean
            im.putpixel((x, y), col)
    for _ in range(6):                         # cross twinkles
        x = rng.randrange(20, BG_W - 20)
        y = rng.randrange(10, 150)
        if (x - 408) ** 2 + (y - 46) ** 2 < 58 ** 2:
            continue
        im.putpixel((x, y), (240, 244, 255))
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            im.putpixel((x + dx, y + dy), (150, 160, 205))


def _planet(im: Image.Image) -> None:
    cx, cy, r = 408, 46, 26
    rrx, rry, tilt = 44, 11, 0.14
    ring_cols = [(232, 194, 126), (186, 146, 88), (122, 92, 62)]

    def ring_q(x: int, y: int) -> tuple[float, float]:
        dx = x - cx
        dy = (y - cy) - dx * tilt
        return (dx / rrx) ** 2 + (dy / rry) ** 2, dy

    def ring_col(x: int) -> tuple:
        if x < cx - 14:
            return ring_cols[0]
        if x < cx + 18:
            return ring_cols[1]
        return ring_cols[2]

    for y in range(cy - 20, cy + 20):          # back half of the ring first
        for x in range(cx - rrx - 2, cx + rrx + 3):
            q, dy = ring_q(x, y)
            if 0.66 <= q <= 1.0 and dy < 0:
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    continue                   # hidden behind the planet
                im.putpixel((x, y), ring_col(x))
    for y in range(cy - r, cy + r + 1):        # planet body, 3-step + terminator
        for x in range(cx - r, cx + r + 1):
            dx, dy = x - cx, y - cy
            q = (dx * dx + dy * dy) / (r * r)
            if q > 1.0:
                continue
            nx, ny = dx / r, dy / r
            t = nx * 0.65 + ny * 0.75
            # bayer jitter (not diagonal-aligned) softens the shade boundaries
            bay = BAYER2[y % 2][x % 2]
            t_eff = t + (bay - 0.625) * 0.30
            # ~1/3 light, 1/3 base, 1/3 dark — a real three-step sphere
            if t_eff < -0.10:
                col = (132, 100, 200)
            elif t_eff > 0.30:
                col = (62, 42, 108)
            else:
                col = (96, 68, 158)
            # latitude bands bent over the sphere, not straight slashes
            lat = (dy - dx * 0.18) / (r * math.sqrt(max(0.05, 1.0 - nx * nx)))
            if -0.42 < lat < -0.22 or 0.12 < lat < 0.34:
                if t < 0.0:                    # lit side: brighten
                    col = (min(255, col[0] + 28), min(255, col[1] + 14),
                           min(255, col[2] + 28))
                else:                          # shadow side: press darker
                    col = (max(0, col[0] - 28), max(0, col[1] - 28),
                           max(0, col[2] - 28))
            limb = 0.90 + (bay - 0.625) * 0.08  # narrow dark limb, dithered inward
            if q > limb:
                col = (int(col[0] * 0.55), int(col[1] * 0.55), int(col[2] * 0.6))
            if q > 0.80 and t < -0.35:
                col = (150, 122, 220)          # lit atmosphere rim
            if q > 0.86 and nx < -0.2 and ny > 0.25:
                col = (96, 208, 235)           # cyan rim light toward the city glow
            im.putpixel((x, y), col)
    for y in range(cy - 20, cy + 22):          # front half of the ring
        for x in range(cx - rrx - 2, cx + rrx + 3):
            q, dy = ring_q(x, y)
            on_sphere = (x - cx) ** 2 + (y - cy) ** 2 <= r * r
            if 0.66 <= q <= 1.0 and dy >= 0:
                if on_sphere:
                    col = ring_cols[0]         # bright gold where the ring crosses
                else:
                    col = ring_col(x)
                    if q > 0.92:
                        col = ring_cols[2]
                im.putpixel((x, y), col)
            elif 1.0 < q <= 1.22 and dy >= 0 and on_sphere:
                rr0, gg0, bb0 = im.getpixel((x, y))[:3]
                im.putpixel((x, y), (int(rr0 * 0.6), int(gg0 * 0.6), int(bb0 * 0.6)))


def _ship(im: Image.Image, x: int, y: int, flip: bool) -> None:
    hull, top = (52, 58, 92), (86, 94, 134)
    dxs = -1 if flip else 1
    for i in range(9):
        im.putpixel((x + i * dxs, y), hull)
        if 1 < i < 8:
            im.putpixel((x + i * dxs, y - 1), top)
    im.putpixel((x + 2 * dxs, y - 1), (96, 210, 235))       # canopy
    im.putpixel((x + 9 * dxs, y), (255, 77, 109))           # nav light
    ex = x - dxs
    for k, f in enumerate((0.85, 0.5, 0.28)):
        blend_px(im, ex - k * 2 * dxs, y, (77, 227, 255), f)


def _crane(im: Image.Image, x: int, top: int) -> None:
    sil = (9, 11, 22)
    for yy in range(top, HORIZON):
        im.putpixel((x, yy), sil)
        im.putpixel((x + 1, yy), sil)
    ImageDraw.Draw(im).rectangle([x - 26, top, x + 30, top + 2], fill=sil)
    ImageDraw.Draw(im).rectangle([x - 26, top + 3, x - 20, top + 8], fill=sil)
    for yy in range(top + 3, top + 20):
        im.putpixel((x + 22, yy), sil)
    ImageDraw.Draw(im).rectangle([x + 21, top + 20, x + 23, top + 22], fill=sil)
    im.putpixel((x, top - 1), (255, 77, 109))               # beacon


NEON_BOARDS = [
    (52, 156, 30, 12, (255, 110, 231)),
    (208, 146, 26, 11, (77, 227, 255)),
    (338, 160, 28, 10, (184, 255, 61)),
]


def draw_background(seed: int = 20260726) -> Image.Image:
    rng = random.Random(seed)
    im = Image.new("RGB", (BG_W, BG_H))

    # 1 sky: dithered navy→violet gradient; violet arrives well above the skyline
    dither_vgradient(im, 0, HORIZON - 1,
                     [(5, 7, 16), (8, 9, 22), (12, 12, 30), (20, 16, 44),
                      (34, 23, 62), (42, 28, 74), (52, 34, 88), (66, 44, 106)])

    # 2 nebulae: each cloud is 2-3 offset lobes of unequal radii so no single
    #   hard ellipse edge survives; grain spills past the rim with radial falloff
    nebs = [
        # violet cloud A, three lobes
        (30, 34, 130, 82, (120, 88, 210, 46)),
        (62, 24, 150, 70, (120, 88, 210, 36)),
        (48, 56, 170, 96, (96, 70, 190, 34)),
        # violet cloud B, two lobes
        (96, 30, 160, 64, (150, 110, 235, 40)),
        (118, 44, 196, 82, (140, 102, 228, 28)),
        # cyan cloud, three quiet lobes
        (318, 58, 404, 100, (60, 200, 210, 30)),
        (352, 46, 436, 92, (66, 210, 218, 22)),
        (340, 78, 448, 114, (70, 220, 225, 22)),
    ]
    neb = Image.new("RGBA", (BG_W, BG_H), (0, 0, 0, 0))
    nd = ImageDraw.Draw(neb)
    for x0, y0, x1, y1, col in nebs:
        nd.ellipse([x0, y0, x1, y1], fill=col)
    neb = neb.filter(ImageFilter.GaussianBlur(5))
    im.paste(Image.alpha_composite(im.convert("RGBA"), neb).convert("RGB"), (0, 0))
    # 1px edge speckle so the mist stays pixel-art.  Seeded random placement —
    # ordered Bayer picks land on the same 3 cells of every 4×4 tile and read
    # as a screen-door over the whole cloud.  Interior (q <= 0.7) stays pure
    # gaussian mist; grain only feathers the rim, with jittered alpha.
    for x0, y0, x1, y1, col in nebs:
        ncx, ncy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        nrx, nry = (x1 - x0) / 2.0, (y1 - y0) / 2.0
        pad_x, pad_y = int(nrx * 0.18) + 1, int(nry * 0.18) + 1
        for yy in range(y0 - pad_y, y1 + pad_y + 1):
            for xx in range(x0 - pad_x, x1 + pad_x + 1):
                q = ((xx - ncx) / nrx) ** 2 + ((yy - ncy) / nry) ** 2
                if q <= 0.7 or q > 1.35:
                    continue
                fall = min(1.0, (1.35 - q) / 0.35)
                if rng.random() < 0.10 * fall:
                    blend_px(im, xx, yy, col[:3], 0.08 + rng.random() * 0.10)

    # 3 stars: three brightness tiers + a few cross twinkles
    _stars(im, rng)

    # 4 ringed planet upper-right
    _planet(im)

    # 5 distant traffic
    _ship(im, 118, 100, False)
    _ship(im, 352, 86, True)

    # 6 far skyline (pure silhouette, roofline held clear above the near layer)
    far, far_hi = (30, 33, 60), (40, 44, 78)
    x = 0
    while x < BG_W:
        bw = rng.randrange(20, 44)
        bh = rng.randrange(34, 59)
        top = 192 - bh
        rect(im, x, top, min(x + bw, BG_W - 1), 191, far)
        hline(im, x, min(x + bw, BG_W - 1), top, far_hi)
        if rng.random() < 0.35:
            ax = x + bw // 2
            rect(im, ax, top - rng.randrange(5, 11), ax, top, far)
        x += bw + rng.randrange(1, 6)

    # 6b warm city glow hugging the horizon
    glow = Image.new("RGBA", (BG_W, BG_H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rectangle([0, 182, BG_W, HORIZON], fill=(120, 70, 140, 34))
    glow = glow.filter(ImageFilter.GaussianBlur(7))
    im.paste(Image.alpha_composite(im.convert("RGBA"), glow).convert("RGB"), (0, 0))

    # 7 near skyline: windows, cranes, cables
    near = (12, 14, 27)
    tops: list[tuple[int, int]] = []
    x = 0
    while x < BG_W:
        bw = rng.randrange(26, 52)
        bh = rng.randrange(20, 43)
        top = HORIZON - bh
        x1 = min(x + bw, BG_W - 1)
        rect(im, x, top, x1, HORIZON - 1, near)
        hline(im, x, x1, top, (20, 23, 42))
        tops.append((x + bw // 2, top))
        for wx in range(x + 3, x1 - 1, 4):     # sparse uneven window lights
            for wy in range(top + 4, HORIZON - 4, 6):
                roll = rng.random()
                if roll < 0.16:
                    c = (255, 205, 110)
                elif roll < 0.24:
                    c = (170, 128, 62)
                elif roll < 0.30:
                    c = (96, 208, 235)
                else:
                    continue
                im.putpixel((wx, wy), c)
                if rng.random() < 0.5:
                    im.putpixel((wx, wy + 1), c)
        if rng.random() < 0.4:
            im.putpixel((x + bw // 2, top - 1), (255, 77, 109))
        x += bw + rng.randrange(1, 5)
    _crane(im, 88, 146)
    _crane(im, 400, 138)
    for (xa, ya), (xb, yb) in ((tops[1], tops[3]), (tops[4], tops[6])):
        for i in range(33):                    # drooping cables
            tt = i / 32
            cx = int(xa + (xb - xa) * tt)
            cyv = int(ya + (yb - ya) * tt + 10 * 4 * tt * (1 - tt))
            if 0 <= cx < BG_W and cyv < HORIZON:
                im.putpixel((cx, cyv), (8, 9, 18))

    # 7b neon ad boards + halo
    halo = Image.new("RGBA", (BG_W, BG_H), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    for bx0, by0, bw, bh, col in NEON_BOARDS:
        rect(im, bx0, by0, bx0 + bw, by0 + bh, (10, 11, 20))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle([bx0, by0, bx0 + bw, by0 + bh], 2, outline=col)
        hline(im, bx0 + 4, bx0 + bw - 10, by0 + 3, col)
        hline(im, bx0 + 4, bx0 + bw - 5, by0 + bh - 4,
              tuple(int(c * 0.72) for c in col))
        px(im, bx0 + bw - 6, by0 + 3, (245, 247, 255))
        vline(im, bx0 + bw // 2, by0 + bh + 1, by0 + bh + 2, (10, 11, 20))
        hd.rounded_rectangle([bx0 - 3, by0 - 3, bx0 + bw + 3, by0 + bh + 3],
                             4, outline=col + (70,), width=3)
    halo = halo.filter(ImageFilter.GaussianBlur(2.6))
    im.paste(Image.alpha_composite(im.convert("RGBA"), halo).convert("RGB"), (0, 0))

    # 8 dock plating: vertical falloff gradient + seams w/ bright ridge + rivets
    dither_vgradient(im, HORIZON, BG_H - 1,
                     [(22, 25, 44), (18, 20, 38), (14, 16, 30), (11, 12, 24)])
    seam_ys = [207, 211, 216, 223, 232, 244, 258]
    for sy in seam_ys:
        hline(im, 0, BG_W - 1, sy - 1, (34, 40, 66))   # lit edge of the plate
        hline(im, 0, BG_W - 1, sy, (10, 11, 22))       # dark seam
    for i in range(len(seam_ys) - 1):
        mid = (seam_ys[i] + seam_ys[i + 1]) // 2
        step = 14 + i * 4
        for rx in range((i * 7) % step, BG_W, step):
            im.putpixel((rx, mid), (44, 50, 80))

    # 9 broken neon reflections (2px, grouped under their boards) + puddles
    def reflect(x0: int, length: int, col: tuple, strength: float) -> None:
        for yy in range(HORIZON + 1, min(BG_H - 1, HORIZON + 1 + length)):
            if (yy + x0) % 4 == 0:
                continue
            fade = 1.0 - (yy - HORIZON) / length
            for xx in (x0, x0 + 1):
                blend_px(im, xx, yy, col, strength * fade)

    for bx0, by0, bw, bh, col in NEON_BOARDS:
        for k in range(3):                     # tidy group right under each board
            reflect(bx0 + 2 + k * max(4, (bw - 6) // 2),
                    rng.randrange(20, 44), col, 0.55)
    for gx0 in (26, 38, 50, 428, 442, 456):    # warm lantern glow, lower corners
        reflect(gx0, rng.randrange(14, 30), (255, 209, 102), 0.4)
    for _ in range(22):                        # faint warm window reflections
        reflect(rng.randrange(BG_W), rng.randrange(5, 14),
                (255, 205, 110) if rng.random() < 0.7 else (96, 208, 235), 0.16)

    for pcx, pcy, prx, col in ((95, 234, 15, (255, 110, 231)),
                               (255, 250, 18, (77, 227, 255)),
                               (402, 224, 13, (184, 255, 61))):
        # water body darker than the deck it sits in, 1px deck-tone rim seats it
        deck_col = im.getpixel((pcx, pcy - 4))[:3]
        pd = ImageDraw.Draw(im)
        pd.ellipse([pcx - prx, pcy - 3, pcx + prx, pcy + 3],
                   fill=(9, 10, 20), outline=deck_col)
        # replay plate seams the ellipse covered: dimmed ridge + darker groove
        for sy in seam_ys:
            for yy, scol in ((sy - 1, (26, 30, 52)), (sy, (6, 7, 14))):
                if pcy - 3 <= yy <= pcy + 3:
                    dyn = (yy - pcy) / 3.5
                    hw = int((prx - 1) * math.sqrt(max(0.0, 1.0 - dyn * dyn)))
                    if hw > 1:
                        hline(im, pcx - hw, pcx + hw, yy, scol)
        # neon reflection shimmer spans the full water width
        for sx in range(pcx - prx + 2, pcx + prx - 1, 3):
            for yy in range(pcy - 2, pcy + 3):
                dxn = (sx - pcx) / prx
                dyn = (yy - pcy) / 3.5
                if dxn * dxn + dyn * dyn > 0.92:
                    continue
                if (yy + sx) % 2:
                    blend_px(im, sx, yy, col, 0.48)
        px(im, pcx - prx + 2, pcy + 2, (60, 66, 100))
        px(im, pcx + prx - 4, pcy - 2, (190, 200, 230))

    # 10 low fog ribbons
    fog = Image.new("RGBA", (BG_W, BG_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fog)
    fd.rectangle([0, 196, BG_W, 207], fill=(150, 135, 190, 22))
    fd.rectangle([0, 236, BG_W, 248], fill=(115, 100, 165, 16))
    fog = fog.filter(ImageFilter.GaussianBlur(6))
    im.paste(Image.alpha_composite(im.convert("RGBA"), fog).convert("RGB"), (0, 0))
    return im


def gen_background() -> None:
    save(upscale(draw_background(), 4), os.path.join(OUT_BG, "bg_dock.png"))


# ─── ui textures ─────────────────────────────────────────────────────────────

def gen_ui() -> None:
    dot = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    for y in range(64):
        for x in range(64):
            d = math.hypot(x - 31.5, y - 31.5) / 32.0
            a = max(0.0, 1.0 - d) ** 2.2
            dot.putpixel((x, y), (255, 255, 255, int(a * 255)))
    save(dot, os.path.join(OUT_UI, "dot_glow.png"))

    vig = Image.new("RGBA", (320, 180), (0, 0, 0, 0))
    for y in range(180):
        for x in range(320):
            dx = (x - 159.5) / 160.0
            dy = (y - 89.5) / 90.0
            rr = math.hypot(dx, dy)
            # tight feather: fully clear until ~85% radius, corners < 15% loss
            a = min(1.0, max(0.0, (rr - 0.85) / 0.5)) ** 2
            vig.putpixel((x, y), (5, 6, 12, int(a * 200)))
    vig = vig.filter(ImageFilter.GaussianBlur(2))
    save(vig, os.path.join(OUT_UI, "vignette.png"))

    scan = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
    for x in range(4):
        scan.putpixel((x, 0), (0, 0, 0, 28))
    save(scan, os.path.join(OUT_UI, "scanlines.png"))


# ─── contact sheets ──────────────────────────────────────────────────────────

SHEET_BG = (16, 18, 30, 255)


def preview_icons() -> None:
    tiles = [upscale(build_icon(pid), 8) for pid in PRODUCT_ORDER]
    pad, tw = 12, tiles[0].width
    sheet = Image.new("RGBA", (4 * (tw + pad) + pad, 2 * (tw + pad) + pad), SHEET_BG)
    for i, t in enumerate(tiles):
        sheet.paste(t, (pad + (i % 4) * (tw + pad), pad + (i // 4) * (tw + pad)), t)
    os.makedirs(PREVIEW, exist_ok=True)
    sheet.convert("RGB").save(os.path.join(PREVIEW, "icons.png"))
    print("preview icons.png")


def preview_characters() -> None:
    names = list(CHARACTERS.keys())
    tiles = [upscale(build_character(n), 4) for n in names]
    pad, tw, th = 12, tiles[0].width, tiles[0].height
    sheet = Image.new("RGBA", (len(names) * (tw + pad) + pad, th + 2 * pad), SHEET_BG)
    for i, t in enumerate(tiles):
        sheet.paste(t, (pad + i * (tw + pad), pad), t)
    os.makedirs(PREVIEW, exist_ok=True)
    sheet.convert("RGB").save(os.path.join(PREVIEW, "characters.png"))
    print("preview characters.png")


def preview_scene() -> None:
    bg = upscale(draw_background(), 2)
    stall = upscale(draw_stall(), 2)
    scene = bg.convert("RGBA")
    sx = (scene.width - stall.width) // 2
    sy = scene.height - stall.height - 20
    scene.paste(stall, (sx, sy), stall)
    for name, cxx in (("customer_dock", sx - 96), ("customer_monk", sx + stall.width + 30)):
        ch = upscale(build_character(name), 2)
        scene.paste(ch, (cxx, scene.height - ch.height - 16), ch)
    os.makedirs(PREVIEW, exist_ok=True)
    scene.convert("RGB").save(os.path.join(PREVIEW, "scene.png"))
    print("preview scene.png")


def main() -> None:
    gen_icons()
    gen_characters()
    gen_stall()
    gen_background()
    gen_ui()
    if "--preview" in sys.argv:
        preview_icons()
        preview_characters()
        preview_scene()
    print("DONE")


if __name__ == "__main__":
    sys.exit(main())
