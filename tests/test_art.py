from __future__ import annotations

from starport_market import art
from starport_market.ui import build_parser


def test_design_palette_covers_every_pyxel_index_once() -> None:
    palette = {
        art.INK,
        art.NIGHT,
        art.PLUM,
        art.MOSS,
        art.RUST,
        art.SLATE,
        art.STEEL,
        art.PAPER,
        art.DANGER,
        art.ORANGE,
        art.AMBER,
        art.MINT,
        art.CYAN,
        art.MUTED,
        art.MAGENTA,
        art.PEACH,
    }
    assert palette == set(range(16))


def test_every_product_has_a_visual_identity() -> None:
    assert set(art.PRODUCT_ACCENTS) == {
        "glow_noodles",
        "plasma_fruit",
        "void_tea",
        "meteor_jerky",
        "holo_charm",
    }
    assert len(set(art.PRODUCT_ACCENTS.values())) == 5


def test_custom_logo_has_every_required_glyph() -> None:
    assert set("STARPORTMARKET") <= set(art.LOGO_GLYPHS)
    assert art.logo_width("STARPORT", 2) == 94
    assert art.logo_width("MARKET", 3) == 105


def test_all_sprite_recipes_stay_inside_the_palette(monkeypatch) -> None:
    colors: list[int] = []

    def record(*args: int) -> None:
        colors.append(args[-1])

    for name in ("rect", "rectb", "line", "pset", "circ", "circb", "tri", "text"):
        monkeypatch.setattr(art.pyxel, name, record)

    for frame, product_id in enumerate(art.PRODUCT_ACCENTS):
        art.product(product_id, 0, 0, frame=frame)
    for kind in range(6):
        art.customer(kind, 0, 0, frame=kind)
    art.vendor(0, 0, frame=7, wave=True)
    art.rank_badge(0, 0)
    art.stall(0, 0, 64)
    art.logo_text("STARPORT", 0, 0, scale=2)

    assert colors
    assert all(0 <= color <= 15 for color in colors)


def test_documentation_capture_modes_are_parseable() -> None:
    parser = build_parser()
    for screen in ("title", "plan", "report", "game_over", "help", "help_tactics"):
        assert parser.parse_args(["--screen", screen]).screen == screen
