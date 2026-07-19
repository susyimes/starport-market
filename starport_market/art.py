"""Code-native pixel art and UI primitives for Starport Market.

The game intentionally uses Pyxel's built-in 16-color palette.  Keeping the
art as tiny deterministic drawing recipes makes it easy to ship, test, and
modify without an external binary resource editor.
"""

from __future__ import annotations

import pyxel


# Pyxel default-palette roles.  Names make the presentation code read like a
# design system instead of a collection of unexplained palette indexes.
INK = 0
NIGHT = 1
PLUM = 2
MOSS = 3
RUST = 4
SLATE = 5
STEEL = 6
PAPER = 7
DANGER = 8
ORANGE = 9
AMBER = 10
MINT = 11
CYAN = 12
MUTED = 13
MAGENTA = 14
PEACH = 15


PRODUCT_ACCENTS = {
    "glow_noodles": AMBER,
    "plasma_fruit": MAGENTA,
    "void_tea": STEEL,
    "meteor_jerky": ORANGE,
    "holo_charm": CYAN,
}


LOGO_GLYPHS = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
}


def panel(
    x: int,
    y: int,
    w: int,
    h: int,
    *,
    title: str | None = None,
    accent: int = CYAN,
    fill: int = INK,
    shadow: bool = True,
) -> None:
    """Draw a layered card with a one-pixel highlight and clipped title tab."""

    if shadow:
        pyxel.rect(x + 2, y + 2, w, h, INK)
    pyxel.rect(x, y, w, h, fill)
    pyxel.rectb(x, y, w, h, SLATE)
    pyxel.line(x + 2, y, x + w - 3, y, accent)
    pyxel.pset(x, y, INK)
    pyxel.pset(x + w - 1, y, INK)
    pyxel.pset(x, y + h - 1, INK)
    pyxel.pset(x + w - 1, y + h - 1, INK)
    if title:
        tab_w = min(w - 8, max(28, len(title) * 4 + 10))
        pyxel.rect(x + 4, y + 3, tab_w, 9, NIGHT)
        pyxel.line(x + 4, y + 12, x + tab_w + 3, y + 12, accent)
        pyxel.text(x + 8, y + 5, title, PAPER)


def inset(x: int, y: int, w: int, h: int, *, color: int = SLATE, fill: int = NIGHT) -> None:
    pyxel.rect(x, y, w, h, fill)
    pyxel.line(x, y, x + w - 1, y, INK)
    pyxel.line(x, y, x, y + h - 1, INK)
    pyxel.line(x + 1, y + h - 1, x + w - 1, y + h - 1, color)
    pyxel.line(x + w - 1, y + 1, x + w - 1, y + h - 1, color)


def chip(x: int, y: int, text: str, *, color: int = CYAN, active: bool = True) -> int:
    width = len(text) * 4 + 8
    fill = color if active else NIGHT
    text_color = INK if active and color in (AMBER, MINT, CYAN, PAPER, PEACH) else PAPER
    pyxel.rect(x + 1, y + 1, width, 9, INK)
    pyxel.rect(x, y, width, 9, fill)
    pyxel.rectb(x, y, width, 9, color if not active else PAPER)
    pyxel.text(x + 4, y + 2, text, text_color)
    return width


def keycap(
    x: int,
    y: int,
    key: str,
    label: str,
    *,
    color: int = CYAN,
    label_color: int = MUTED,
) -> int:
    key_w = len(key) * 4 + 6
    pyxel.rect(x + 1, y + 1, key_w, 9, INK)
    pyxel.rect(x, y, key_w, 9, color)
    pyxel.rectb(x, y, key_w, 9, PAPER)
    pyxel.text(x + 3, y + 2, key, INK)
    pyxel.text(x + key_w + 4, y + 2, label, label_color)
    return key_w + 6 + len(label) * 4


def bar(
    x: int,
    y: int,
    w: int,
    value: float,
    maximum: float,
    *,
    color: int = MINT,
    danger_at: float | None = None,
) -> None:
    pyxel.rect(x, y, w, 5, INK)
    pyxel.rectb(x, y, w, 5, SLATE)
    ratio = 0.0 if maximum <= 0 else max(0.0, min(1.0, value / maximum))
    fill = max(0, int((w - 2) * ratio))
    if danger_at is not None and ratio >= danger_at:
        color = DANGER
    if fill:
        pyxel.rect(x + 1, y + 1, fill, 3, color)
    for marker in range(x + 8, x + w - 1, 8):
        pyxel.pset(marker, y + 2, NIGHT)


def metric(x: int, y: int, label: str, value: str, *, icon_name: str, color: int) -> None:
    icon(icon_name, x, y + 1, color)
    pyxel.text(x + 10, y, label, MUTED)
    pyxel.text(x + 10, y + 8, value, color)


def icon(name: str, x: int, y: int, color: int = CYAN) -> None:
    """Draw a compact 7x7 semantic icon."""

    if name == "credit":
        pyxel.circb(x + 3, y + 3, 3, color)
        pyxel.line(x + 2, y + 2, x + 5, y + 2, color)
        pyxel.line(x + 1, y + 4, x + 4, y + 4, color)
    elif name == "rep":
        pyxel.line(x + 3, y, x + 4, y + 2, color)
        pyxel.line(x + 4, y + 2, x + 6, y + 2, color)
        pyxel.line(x + 6, y + 2, x + 4, y + 4, color)
        pyxel.line(x + 4, y + 4, x + 5, y + 6, color)
        pyxel.line(x + 5, y + 6, x + 3, y + 5, color)
        pyxel.line(x + 3, y + 5, x + 1, y + 6, color)
        pyxel.line(x + 1, y + 6, x + 2, y + 4, color)
        pyxel.line(x + 2, y + 4, x, y + 2, color)
        pyxel.line(x, y + 2, x + 2, y + 2, color)
        pyxel.line(x + 2, y + 2, x + 3, y, color)
    elif name == "cargo":
        pyxel.rectb(x, y + 1, 7, 6, color)
        pyxel.line(x, y + 3, x + 6, y + 3, color)
        pyxel.line(x + 3, y + 1, x + 3, y + 6, color)
    elif name == "day":
        pyxel.rectb(x, y + 1, 7, 6, color)
        pyxel.line(x + 1, y + 3, x + 5, y + 3, color)
        pyxel.pset(x + 2, y, color)
        pyxel.pset(x + 5, y, color)
    elif name == "signal":
        pyxel.pset(x, y + 6, color)
        pyxel.line(x + 2, y + 6, x + 2, y + 4, color)
        pyxel.line(x + 4, y + 6, x + 4, y + 2, color)
        pyxel.line(x + 6, y + 6, x + 6, y, color)
    elif name == "campaign":
        pyxel.line(x, y + 3, x + 4, y + 1, color)
        pyxel.line(x, y + 3, x + 4, y + 5, color)
        pyxel.line(x + 4, y + 1, x + 4, y + 5, color)
        pyxel.line(x + 1, y + 4, x + 2, y + 7, color)
        pyxel.pset(x + 6, y, color)
        pyxel.pset(x + 6, y + 6, color)
    elif name == "upgrade":
        pyxel.rect(x + 2, y + 2, 3, 3, color)
        for dx, dy in ((3, 0), (3, 6), (0, 3), (6, 3)):
            pyxel.pset(x + dx, y + dy, color)
    elif name == "profit":
        pyxel.line(x, y + 6, x + 2, y + 4, color)
        pyxel.line(x + 2, y + 4, x + 4, y + 5, color)
        pyxel.line(x + 4, y + 5, x + 7, y + 1, color)
        pyxel.line(x + 5, y + 1, x + 7, y + 1, color)
        pyxel.line(x + 7, y + 1, x + 7, y + 3, color)
    elif name == "waste":
        pyxel.rectb(x + 1, y + 2, 5, 5, color)
        pyxel.line(x, y + 1, x + 6, y + 1, color)
        pyxel.pset(x + 2, y, color)
        pyxel.pset(x + 4, y, color)
    elif name == "people":
        pyxel.circ(x + 2, y + 2, 1, color)
        pyxel.circ(x + 5, y + 2, 1, color)
        pyxel.rect(x, y + 4, 4, 3, color)
        pyxel.rect(x + 4, y + 4, 3, 3, color)
    elif name == "medal":
        pyxel.circ(x + 3, y + 2, 2, color)
        pyxel.line(x + 2, y + 4, x + 1, y + 7, color)
        pyxel.line(x + 4, y + 4, x + 5, y + 7, color)
    else:
        pyxel.rectb(x, y, 7, 7, color)
        pyxel.pset(x + 3, y + 3, color)


def logo_width(text: str, scale: int = 1) -> int:
    if not text:
        return 0
    return len(text) * (5 * scale + scale) - scale


def logo_text(
    text: str,
    x: int,
    y: int,
    *,
    scale: int = 1,
    color: int = PAPER,
    shadow: int | None = INK,
) -> None:
    if shadow is not None:
        _logo_text_pass(text, x + scale, y + scale, scale, shadow)
    _logo_text_pass(text, x, y, scale, color)


def _logo_text_pass(text: str, x: int, y: int, scale: int, color: int) -> None:
    cursor = x
    for character in text:
        glyph = LOGO_GLYPHS.get(character)
        if glyph:
            for row, pixels in enumerate(glyph):
                for column, pixel in enumerate(pixels):
                    if pixel == "1":
                        pyxel.rect(
                            cursor + column * scale,
                            y + row * scale,
                            scale,
                            scale,
                            color,
                        )
        cursor += 6 * scale


def product(product_id: str, x: int, y: int, scale: int = 1, *, frame: int = 0) -> None:
    """Draw one readable 8x8 product sprite."""

    s = scale
    accent = PRODUCT_ACCENTS[product_id]
    if product_id == "glow_noodles":
        pyxel.rect(x + s, y + 4 * s, 6 * s, 3 * s, RUST)
        pyxel.line(x, y + 4 * s, x + 7 * s, y + 4 * s, PAPER)
        pyxel.line(x + s, y + 7 * s, x + 6 * s, y + 7 * s, accent)
        pyxel.pset(x + (2 + frame % 2) * s, y + 2 * s, accent)
        pyxel.pset(x + (5 - frame % 2) * s, y + s, accent)
    elif product_id == "plasma_fruit":
        pyxel.circ(x + 4 * s, y + 4 * s, 3 * s, accent)
        pyxel.circb(x + 4 * s, y + 4 * s, 3 * s, PAPER)
        pyxel.pset(x + 3 * s, y + 3 * s, PEACH)
        pyxel.line(x + 4 * s, y + s, x + 6 * s, y, MINT)
    elif product_id == "void_tea":
        pyxel.rect(x + s, y + 2 * s, 6 * s, 5 * s, PLUM)
        pyxel.rectb(x + s, y + 2 * s, 6 * s, 5 * s, STEEL)
        pyxel.line(x + 7 * s, y + 3 * s, x + 8 * s, y + 5 * s, STEEL)
        pyxel.pset(x + (3 + frame % 2) * s, y, CYAN)
    elif product_id == "meteor_jerky":
        pyxel.line(x, y + 6 * s, x + 6 * s, y + s, RUST)
        pyxel.line(x + s, y + 7 * s, x + 7 * s, y + 2 * s, accent)
        pyxel.pset(x + 4 * s, y + 3 * s, PEACH)
        pyxel.pset(x + 6 * s, y + 2 * s, PAPER)
    else:
        pyxel.line(x + 4 * s, y, x + 8 * s, y + 4 * s, CYAN)
        pyxel.line(x + 8 * s, y + 4 * s, x + 4 * s, y + 8 * s, PAPER)
        pyxel.line(x + 4 * s, y + 8 * s, x, y + 4 * s, CYAN)
        pyxel.line(x, y + 4 * s, x + 4 * s, y, PAPER)
        pyxel.circ(x + 4 * s, y + 4 * s, max(1, s), MAGENTA if frame % 2 else accent)


def vendor(x: int, y: int, scale: int = 1, *, frame: int = 0, wave: bool = False) -> None:
    """Draw M0X, the expressive 15x19 market vendor robot."""

    s = scale
    bob = (frame // 8) % 2 * s
    y += bob
    # Antenna and ear lights.
    pyxel.line(x + 7 * s, y, x + 7 * s, y + 2 * s, STEEL)
    pyxel.circ(x + 7 * s, y, max(1, s - 1), AMBER if frame % 16 < 8 else MAGENTA)
    pyxel.rect(x + 2 * s, y + 3 * s, 11 * s, 8 * s, MUTED)
    pyxel.rectb(x + 2 * s, y + 3 * s, 11 * s, 8 * s, PAPER)
    pyxel.rect(x + 3 * s, y + 6 * s, 9 * s, 3 * s, NIGHT)
    eye_shift = 1 if frame % 30 > 24 else 0
    pyxel.rect(x + (4 + eye_shift) * s, y + 7 * s, s, s, CYAN)
    pyxel.rect(x + (9 + eye_shift) * s, y + 7 * s, s, s, CYAN)
    pyxel.pset(x + s, y + 6 * s, MAGENTA)
    pyxel.pset(x + 13 * s, y + 6 * s, MINT)
    # Apron body and glowing register badge.
    pyxel.rect(x + 4 * s, y + 11 * s, 7 * s, 6 * s, SLATE)
    pyxel.rectb(x + 4 * s, y + 11 * s, 7 * s, 6 * s, STEEL)
    pyxel.rect(x + 6 * s, y + 12 * s, 3 * s, 3 * s, PLUM)
    pyxel.pset(x + 7 * s, y + 13 * s, AMBER)
    # Arms: one can wave on title/report screens.
    pyxel.line(x + 4 * s, y + 12 * s, x, y + 14 * s, STEEL)
    if wave:
        hand_y = y + (8 if frame % 20 < 10 else 7) * s
        pyxel.line(x + 11 * s, y + 12 * s, x + 15 * s, hand_y, STEEL)
        pyxel.pset(x + 15 * s, hand_y - s, AMBER)
    else:
        pyxel.line(x + 11 * s, y + 12 * s, x + 15 * s, y + 14 * s, STEEL)
    pyxel.line(x + 5 * s, y + 17 * s, x + 3 * s, y + 19 * s, MUTED)
    pyxel.line(x + 10 * s, y + 17 * s, x + 12 * s, y + 19 * s, MUTED)


CUSTOMER_COLORS = (STEEL, ORANGE, MAGENTA, PAPER, MOSS, PEACH)


def customer(kind: int, x: int, y: int, *, frame: int = 0) -> None:
    """Draw one of six recognizable 10x15 customer silhouettes."""

    kind %= 6
    color = CUSTOMER_COLORS[kind]
    step = (frame // 6 + kind) % 2
    if kind == 0:  # Dock worker: square helmet and broad shoulders.
        pyxel.rect(x + 2, y + 1, 7, 6, color)
        pyxel.rect(x + 1, y + 2, 9, 2, AMBER)
        pyxel.rect(x, y + 8, 11, 6, color)
        pyxel.rect(x + 4, y + 9, 3, 3, NIGHT)
    elif kind == 1:  # Pilot: visor and flight collar.
        pyxel.circ(x + 5, y + 4, 4, color)
        pyxel.line(x + 2, y + 4, x + 8, y + 4, CYAN)
        pyxel.rect(x + 2, y + 8, 7, 6, color)
        pyxel.line(x + 2, y + 9, x + 8, y + 12, PAPER)
    elif kind == 2:  # Tourist: cap, camera, backpack.
        pyxel.circ(x + 5, y + 4, 3, color)
        pyxel.line(x + 3, y, x + 9, y + 2, AMBER)
        pyxel.rect(x + 2, y + 8, 7, 6, color)
        pyxel.rect(x + 4, y + 9, 4, 3, INK)
        pyxel.pset(x + 6, y + 10, CYAN)
        pyxel.rect(x, y + 8, 2, 5, PLUM)
    elif kind == 3:  # Monk: pointed hood and robe.
        pyxel.tri(x + 5, y, x + 1, y + 8, x + 9, y + 8, color)
        pyxel.circ(x + 5, y + 5, 2, INK)
        pyxel.rect(x + 1, y + 8, 9, 7, color)
        pyxel.line(x + 5, y + 9, x + 5, y + 14, CYAN)
    elif kind == 4:  # Scrap trader: goggles and tool pack.
        pyxel.circ(x + 5, y + 4, 3, color)
        pyxel.rect(x + 1, y + 3, 9, 3, INK)
        pyxel.pset(x + 3, y + 4, MINT)
        pyxel.pset(x + 7, y + 4, MINT)
        pyxel.rect(x + 2, y + 8, 7, 6, color)
        pyxel.line(x + 9, y + 9, x + 11, y + 5, RUST)
    else:  # Luxe envoy: tall headpiece and tailored coat.
        pyxel.tri(x + 5, y, x + 2, y + 5, x + 8, y + 5, MAGENTA)
        pyxel.circ(x + 5, y + 5, 3, color)
        pyxel.rect(x + 2, y + 8, 7, 6, color)
        pyxel.line(x + 5, y + 8, x + 5, y + 13, AMBER)
    pyxel.line(x + 3, y + 14, x + 2 - step, y + 16, color)
    pyxel.line(x + 7, y + 14, x + 8 + step, y + 16, color)


def rank_badge(x: int, y: int, *, color: int = AMBER, scale: int = 1) -> None:
    s = scale
    pyxel.circ(x + 8 * s, y + 8 * s, 8 * s, SLATE)
    pyxel.circb(x + 8 * s, y + 8 * s, 8 * s, PAPER)
    pyxel.circb(x + 8 * s, y + 8 * s, 6 * s, color)
    pyxel.line(x + 5 * s, y + 17 * s, x + 3 * s, y + 23 * s, color)
    pyxel.line(x + 3 * s, y + 23 * s, x + 8 * s, y + 20 * s, color)
    pyxel.line(x + 11 * s, y + 17 * s, x + 13 * s, y + 23 * s, color)
    pyxel.line(x + 13 * s, y + 23 * s, x + 8 * s, y + 20 * s, color)
    icon("rep", x + 5 * s, y + 5 * s, color)


def stall(x: int, y: int, w: int, *, frame: int = 0) -> None:
    """Draw the branded market awning and sales counter."""

    pyxel.rect(x + 6, y + 16, w - 12, 34, SLATE)
    pyxel.rect(x, y + 10, w, 9, PLUM)
    segment = 14
    for sx in range(x, x + w, segment):
        color = MAGENTA if (sx // segment) % 2 else CYAN
        pyxel.rect(sx, y + 10, min(segment, x + w - sx), 7, color)
        pyxel.tri(sx, y + 17, min(sx + segment, x + w), y + 17, sx + segment // 2, y + 22, color)
    pyxel.rect(x + 8, y + 22, w - 16, 21, NIGHT)
    pyxel.rect(x + 3, y + 43, w - 6, 10, RUST)
    pyxel.line(x + 4, y + 43, x + w - 5, y + 43, AMBER)
    pyxel.rect(x + w // 2 - 26, y, 52, 10, INK)
    pyxel.rectb(x + w // 2 - 26, y, 52, 10, CYAN)
    pyxel.text(x + w // 2 - 20, y + 2, "M0X MARKET", CYAN if frame % 30 < 24 else PAPER)


def skyline(base_y: int, *, frame: int = 0, layer: int = 0) -> None:
    color = SLATE if layer == 0 else INK
    step = 19 if layer == 0 else 27
    offset = (frame // (18 if layer == 0 else 35)) % step
    for index, x in enumerate(range(-step - offset, 320 + step, step)):
        height = 9 + ((index * 11 + layer * 7) % (24 if layer == 0 else 16))
        width = step - 3
        pyxel.rect(x, base_y - height, width, height, color)
        if layer == 0 and index % 2 == 0:
            pyxel.pset(x + 4, base_y - height + 5, AMBER)
            pyxel.pset(x + 10, base_y - height + 10, CYAN)


def transition(age: int) -> None:
    """A short diagonal shutter reveal; fully gone after eight frames."""

    if age >= 8:
        return
    reveal = age * 48
    for y in range(0, 240, 8):
        covered = max(0, 320 - reveal + (y % 16) * 2)
        if covered:
            pyxel.rect(320 - covered, y, covered, 8, INK)
