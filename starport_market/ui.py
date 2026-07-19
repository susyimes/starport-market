"""Pyxel presentation layer for human players."""

from __future__ import annotations

import argparse
import math
import os
import random
from typing import Any

import pyxel

from . import __version__, art
from .core import InvalidAction, MarketGame
from .bot import HeuristicAgent


WIDTH = 320
HEIGHT = 240


def _money(value: int) -> str:
    sign = "-" if value < 0 else ""
    return f"{sign}${abs(value)}"


def _clip(text: str, limit: int) -> str:
    """Trim to a character budget without cutting a word in half."""

    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0]
    if not cut:
        cut = text[:limit]
    return cut.rstrip(" ,;:")


def _join_tags(tags: list[str], limit: int) -> str:
    """Join tags with slashes, dropping whole tags that exceed the budget."""

    out = ""
    for tag in tags:
        candidate = tag.upper() if not out else f"{out}/{tag.upper()}"
        if len(candidate) > limit:
            break
        out = candidate
    return out


def _wrap(text: str, characters: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if len(candidate) <= characters:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


class GameApp:
    def __init__(
        self,
        seed: int = 7,
        *,
        start_screen: str = "title",
        capture_path: str | None = None,
    ) -> None:
        self.seed = seed
        self.game = MarketGame(seed=seed)
        self.mode = start_screen
        self.mode_enter_frame = 0
        self.capture_path = os.path.abspath(capture_path) if capture_path else None
        self.selected_product = 0
        self.plan_orders: dict[str, int] = {}
        self.plan_prices: dict[str, int] = {}
        self.campaign_index = 0
        self.upgrade_index = 0
        self.report: dict[str, Any] | None = None
        self.help_visible = False
        self.help_page = 0
        self.toast = ""
        self.toast_color = 7
        self.toast_until = 0
        self.stars = self._make_stars(seed)
        self.sparkles: list[dict[str, float]] = []

        pyxel.init(
            WIDTH,
            HEIGHT,
            title="Starport Market",
            fps=30,
            display_scale=3,
        )
        pyxel.mouse(False)
        self._configure_audio()
        self._reset_plan()
        self._prepare_demo_screen(start_screen)
        pyxel.run(self.update, self.draw)

    @staticmethod
    def _make_stars(seed: int) -> list[tuple[int, int, int, int]]:
        rng = random.Random(seed ^ 0x51A7)
        return [
            (rng.randrange(WIDTH), rng.randrange(HEIGHT), rng.choice((5, 6, 12)), rng.choice((1, 1, 2)))
            for _ in range(52)
        ]

    @staticmethod
    def _configure_audio() -> None:
        try:
            sounds = pyxel.sounds
            sounds[0].set("c3e3g3c4", "t", "6", "n", 12)
            sounds[1].set("g3c4e4", "s", "5", "f", 10)
            sounds[2].set("f2c2", "n", "5", "f", 12)
            sounds[3].set("c2c2g2c3", "p", "4", "n", 8)
        except Exception:
            pass

    @property
    def product_ids(self) -> tuple[str, ...]:
        return self.game.product_ids

    @property
    def campaign_ids(self) -> list[str | None]:
        return [None, *self.game.campaigns]

    @property
    def upgrade_ids(self) -> list[str | None]:
        return [None, *self.game.upgrades]

    def _play_sound(self, sound_id: int) -> None:
        try:
            pyxel.play(0, sound_id)
        except Exception:
            pass

    def _reset_plan(self) -> None:
        self.plan_orders = {product_id: 0 for product_id in self.product_ids}
        self.plan_prices = dict(self.game.state["prices"])
        self.campaign_index = 0
        self.upgrade_index = 0
        self.selected_product = min(self.selected_product, len(self.product_ids) - 1)

    def _prepare_demo_screen(self, start_screen: str) -> None:
        if start_screen in {"help", "help_tactics"}:
            self.mode = "title"
            self.help_visible = True
            self.help_page = 1 if start_screen == "help_tactics" else 0
            return
        if start_screen not in {"report", "game_over"}:
            return
        agent = HeuristicAgent()
        while not self.game.state["done"]:
            action = agent.act(self.game.observation())
            transition = self.game.step(action)
            self.report = transition["report"]
            if start_screen == "report" or transition["terminated"]:
                break
        self.mode = start_screen

    def _action(self) -> dict[str, Any]:
        return {
            "orders": dict(self.plan_orders),
            "prices": dict(self.plan_prices),
            "campaign": self.campaign_ids[self.campaign_index],
            "upgrade": self.upgrade_ids[self.upgrade_index],
        }

    def _show_toast(self, text: str, color: int = 7, duration: int = 90) -> None:
        self.toast = text
        self.toast_color = color
        self.toast_until = pyxel.frame_count + duration

    def _set_mode(self, mode: str) -> None:
        self.mode = mode
        self.mode_enter_frame = pyxel.frame_count

    def _screen_age(self) -> int:
        return max(0, pyxel.frame_count - self.mode_enter_frame)

    def _pressed(self, key: int, repeat: bool = False) -> bool:
        return pyxel.btnp(key, 12, 3) if repeat else pyxel.btnp(key)

    def update(self) -> None:
        # Let entrance animation and sprite blinks settle before deterministic
        # documentation captures are written.
        if self.capture_path and pyxel.frame_count >= 30:
            pyxel.screen.save(self.capture_path, 1)
            pyxel.quit()
            return
        if self._pressed(pyxel.KEY_H):
            self.help_visible = not self.help_visible
            self._play_sound(1)
            return
        if self.help_visible:
            if self._pressed(pyxel.KEY_LEFT) or self._pressed(pyxel.KEY_RIGHT):
                self.help_page = 1 - self.help_page
            return

        if self.mode == "title":
            self._update_title()
        elif self.mode == "plan":
            self._update_plan()
        elif self.mode == "report":
            self._update_report()
        elif self.mode == "game_over":
            self._update_game_over()

        self._update_sparkles()

    def _update_title(self) -> None:
        if self._pressed(pyxel.KEY_SPACE) or self._pressed(pyxel.KEY_RETURN):
            self._set_mode("plan")
            self._play_sound(0)

    def _update_plan(self) -> None:
        if self._pressed(pyxel.KEY_UP, repeat=True):
            self.selected_product = (self.selected_product - 1) % len(self.product_ids)
            self._play_sound(1)
        if self._pressed(pyxel.KEY_DOWN, repeat=True):
            self.selected_product = (self.selected_product + 1) % len(self.product_ids)
            self._play_sound(1)

        product_id = self.product_ids[self.selected_product]
        if self._pressed(pyxel.KEY_LEFT, repeat=True):
            self._adjust_order(product_id, -1)
        if self._pressed(pyxel.KEY_RIGHT, repeat=True):
            self._adjust_order(product_id, 1)
        if self._pressed(pyxel.KEY_Z, repeat=True):
            self._adjust_price(product_id, -1)
        if self._pressed(pyxel.KEY_X, repeat=True):
            self._adjust_price(product_id, 1)

        if self._pressed(pyxel.KEY_C):
            self.campaign_index = (self.campaign_index + 1) % len(self.campaign_ids)
            self._play_sound(1)
        if self._pressed(pyxel.KEY_U):
            self._cycle_upgrade()

        if self._pressed(pyxel.KEY_SPACE) or self._pressed(pyxel.KEY_RETURN):
            self._open_market()

    def _adjust_order(self, product_id: str, delta: int) -> None:
        old = self.plan_orders[product_id]
        self.plan_orders[product_id] = max(0, min(99, old + delta))
        try:
            self.game.quote_action(self._action())
            self._play_sound(1)
        except InvalidAction as exc:
            self.plan_orders[product_id] = old
            self._show_toast(str(exc), 8, 60)
            self._play_sound(2)

    def _adjust_price(self, product_id: str, delta: int) -> None:
        low, high = self.game.price_bounds(product_id)
        self.plan_prices[product_id] = max(low, min(high, self.plan_prices[product_id] + delta))
        self._play_sound(1)

    def _cycle_upgrade(self) -> None:
        for _ in range(len(self.upgrade_ids)):
            self.upgrade_index = (self.upgrade_index + 1) % len(self.upgrade_ids)
            upgrade_id = self.upgrade_ids[self.upgrade_index]
            if upgrade_id is None:
                break
            item = self.game.upgrades[upgrade_id]
            if self.game.state["upgrade_levels"][upgrade_id] < item["max_level"]:
                break
        self._play_sound(1)

    def _open_market(self) -> None:
        try:
            transition = self.game.step(self._action())
        except InvalidAction as exc:
            self._show_toast(str(exc), 8, 120)
            self._play_sound(2)
            return
        self.report = transition["report"]
        self._set_mode("report")
        self._spawn_sparkles(max(4, min(22, self.report["units_sold"] // 2)))
        self._play_sound(0 if self.report["profit"] >= 0 else 2)

    def _update_report(self) -> None:
        if self._pressed(pyxel.KEY_SPACE) or self._pressed(pyxel.KEY_RETURN):
            if self.game.state["done"]:
                self._set_mode("game_over")
                self._spawn_sparkles(40)
                self._play_sound(3)
            else:
                self._reset_plan()
                self._set_mode("plan")
                self._play_sound(1)

    def _update_game_over(self) -> None:
        if self._pressed(pyxel.KEY_R):
            self.seed += 1
            self.game = MarketGame(seed=self.seed)
            self.report = None
            self._reset_plan()
            self._set_mode("plan")
            self._play_sound(0)
        elif self._pressed(pyxel.KEY_T):
            self.game = MarketGame(seed=self.seed)
            self.report = None
            self._reset_plan()
            self._set_mode("title")

    def _spawn_sparkles(self, count: int) -> None:
        rng = random.Random(self.game.state_digest())
        for _ in range(count):
            self.sparkles.append(
                {
                    "x": rng.randrange(24, WIDTH - 24),
                    "y": rng.randrange(45, HEIGHT - 20),
                    "vx": rng.uniform(-0.4, 0.4),
                    "vy": rng.uniform(-1.2, -0.3),
                    "life": rng.randrange(25, 70),
                    "color": rng.choice((9, 10, 12, 14)),
                }
            )

    def _update_sparkles(self) -> None:
        kept = []
        for sparkle in self.sparkles:
            sparkle["x"] += sparkle["vx"]
            sparkle["y"] += sparkle["vy"]
            sparkle["vy"] += 0.025
            sparkle["life"] -= 1
            if sparkle["life"] > 0:
                kept.append(sparkle)
        self.sparkles = kept

    def draw(self) -> None:
        self._draw_space()
        if self.mode == "title":
            self._draw_title()
        elif self.mode == "plan":
            self._draw_plan()
        elif self.mode == "report":
            self._draw_report()
        elif self.mode == "game_over":
            self._draw_game_over()

        for sparkle in self.sparkles:
            pyxel.pset(int(sparkle["x"]), int(sparkle["y"]), int(sparkle["color"]))
        if self.help_visible:
            self._draw_help()
        elif not self.capture_path:
            art.transition(self._screen_age())

    def _draw_space(self) -> None:
        pyxel.cls(art.NIGHT)
        frame = pyxel.frame_count
        # A restrained dither nebula makes empty space feel intentional while
        # preserving contrast behind every information card.
        for x in range(24, WIDTH, 17):
            y = 28 + ((x * 13 + self.seed * 7) % 128)
            if (x + frame // 8) % 3:
                pyxel.pset(x, y, art.PLUM)
        for x, y, color, speed in self.stars:
            sy = (y + frame // max(1, 5 - speed)) % HEIGHT
            pyxel.pset(x, sy, color if (frame + x) % 22 else art.PAPER)

        # Dock moon and orbital traffic sit behind the UI on every screen.
        pyxel.circ(274, 45, 23, art.SLATE)
        pyxel.circ(268, 39, 18, art.MUTED)
        pyxel.circ(263, 34, 11, art.STEEL)
        pyxel.line(242, 48, 305, 35, art.PLUM)
        pyxel.line(243, 50, 306, 37, art.MAGENTA)
        traffic_x = (frame * 2 + self.seed * 11) % 360 - 20
        pyxel.line(traffic_x - 8, 72, traffic_x, 72, art.PLUM)
        pyxel.pset(traffic_x, 72, art.CYAN)

        art.skyline(221, frame=frame, layer=0)
        art.skyline(238, frame=frame, layer=1)
        pyxel.rect(0, 232, WIDTH, 8, art.INK)
        pyxel.line(0, 232, WIDTH, 232, art.CYAN)

    @staticmethod
    def _panel(x: int, y: int, w: int, h: int, title: str | None = None, color: int = 5) -> None:
        art.panel(x, y, w, h, title=title, accent=color)

    def _draw_title(self) -> None:
        frame = pyxel.frame_count
        pulse = art.AMBER if (frame // 14) % 2 else art.ORANGE

        # Hanging dock marker and the two-line hand-built logo replace the old
        # empty title rectangle with a recognizable product identity.
        pyxel.line(23, 0, 23, 21, art.STEEL)
        art.chip(7, 19, "DOCK 7", color=art.CYAN)
        top = "STARPORT"
        top_x = (WIDTH - art.logo_width(top, 2)) // 2
        art.logo_text(top, top_x, 22, scale=2, color=art.CYAN, shadow=art.PLUM)
        bottom = "MARKET"
        bottom_x = (WIDTH - art.logo_width(bottom, 3)) // 2
        art.logo_text(bottom, bottom_x, 47, scale=3, color=pulse, shadow=art.RUST)
        pyxel.line(83, 72, 237, 72, art.MAGENTA)
        pyxel.text(94, 77, "18 NIGHTS // BUILD YOUR ORBIT", art.PAPER)

        # Branded stall key art, stocked shelves, and recognizable customers.
        art.stall(42, 94, 236, frame=frame)
        shelf_x = (68, 103, 202, 237)
        shelf_items = ("glow_noodles", "plasma_fruit", "meteor_jerky", "holo_charm")
        for x, product_id in zip(shelf_x, shelf_items, strict=True):
            art.product(product_id, x, 117, 2, frame=frame // 8)
        art.vendor(145, 108, 2, frame=frame, wave=True)
        art.customer(0, 47, 143, frame=frame)
        art.customer(2, 78, 147, frame=frame + 4)
        art.customer(3, 244, 145, frame=frame + 8)
        art.customer(5, 274, 148, frame=frame + 12)
        pyxel.line(20, 169, 300, 169, art.SLATE)
        for x in range(22, 302, 18):
            pyxel.pset(x, 172 + (x // 18) % 2, art.PLUM)

        art.panel(76, 178, 168, 24, accent=pulse, fill=art.NIGHT)
        arrow = ">" if (frame // 12) % 2 else " "
        pyxel.text(91, 186, f"{arrow} SPACE  OPEN THE STALL {arrow}", art.PAPER)
        art.keycap(103, 208, "H", "FIELD GUIDE", color=art.CYAN)
        pyxel.text(8, 228, f"SEED {self.seed:04}", art.MUTED)
        version_text = f"V{__version__}  HUMAN + AGENT"
        pyxel.text(WIDTH - len(version_text) * 4 - 8, 228, version_text, art.MUTED)

    @staticmethod
    def _draw_vendor(x: int, y: int, scale: int = 1) -> None:
        art.vendor(x, y, scale, frame=pyxel.frame_count)

    def _draw_header(self, day_override: int | None = None) -> None:
        pyxel.rect(0, 0, WIDTH, 22, art.INK)
        pyxel.line(0, 21, WIDTH, 21, art.CYAN)
        day = self.game.state["day"] if day_override is None else day_override
        used = self.game.inventory_count()
        capacity = self.game.capacity()
        art.icon("day", 5, 7, art.CYAN)
        pyxel.text(15, 3, "NIGHT", art.MUTED)
        pyxel.text(15, 11, f"{day:02}/{self.game.state['total_days']:02}", art.PAPER)
        pyxel.line(58, 3, 58, 18, art.SLATE)
        art.icon("credit", 65, 7, art.AMBER)
        pyxel.text(75, 3, "CREDITS", art.MUTED)
        pyxel.text(75, 11, _money(self.game.state["cash"]), art.AMBER)
        pyxel.line(139, 3, 139, 18, art.SLATE)
        art.icon("rep", 146, 7, art.MAGENTA)
        pyxel.text(156, 3, "REPUTATION", art.MUTED)
        pyxel.text(156, 11, f"{self.game.state['reputation']:.0f}", art.MAGENTA)
        art.bar(177, 12, 34, self.game.state["reputation"], 100, color=art.MAGENTA)
        pyxel.line(216, 3, 216, 18, art.SLATE)
        art.icon("cargo", 223, 7, art.STEEL)
        pyxel.text(233, 3, "CARGO", art.MUTED)
        pyxel.text(233, 11, f"{used}/{capacity}", art.PAPER)
        art.bar(257, 12, 28, used, capacity, color=art.CYAN, danger_at=0.9)
        art.chip(291, 6, "H", color=art.SLATE, active=False)

    def _draw_plan(self) -> None:
        self._draw_header()
        observation = self.game.observation()
        event = observation["market"]["event"]
        group = observation["market"]["customer_group"]
        art.panel(5, 25, 310, 30, accent=art.MAGENTA, fill=art.INK, shadow=False)
        art.icon("signal", 11, 32, art.MAGENTA)
        pyxel.text(22, 29, "PORT SIGNAL", art.MUTED)
        pyxel.text(76, 29, event["name"].upper()[:23], art.MAGENTA)
        crowd_label = group["name"].upper()[:16]
        crowd_x = 311 - (len(crowd_label) * 4 + 8)
        art.chip(crowd_x, 29, crowd_label, color=art.CYAN, active=False)
        pyxel.text(22, 41, event["headline"][:43], art.PAPER)
        likes = _join_tags(group["preferred_tags"], 22)
        pyxel.text(218, 42, "LIKES " + likes, art.STEEL)

        art.panel(5, 59, 209, 130, title="CARGO MANIFEST", accent=art.CYAN)
        pyxel.rect(8, 73, 203, 9, art.NIGHT)
        pyxel.text(21, 75, "ITEM", art.MUTED)
        pyxel.text(63, 75, "HAVE", art.MUTED)
        pyxel.text(89, 75, "COST", art.MUTED)
        pyxel.text(116, 75, "LOAD", art.MUTED)
        pyxel.text(148, 75, "ASK", art.MUTED)
        pyxel.text(175, 75, "FCST", art.MUTED)
        for index, product_id in enumerate(self.product_ids):
            product = observation["products"][product_id]
            y = 85 + index * 19
            selected = index == self.selected_product
            if selected:
                pyxel.rect(7, y - 2, 205, 18, art.PLUM)
                pyxel.line(7, y - 2, 7, y + 15, art.CYAN)
                pyxel.text(9, y + 8, ">" if (pyxel.frame_count // 8) % 2 else " ", art.CYAN)
            elif index % 2:
                pyxel.rect(7, y - 2, 205, 18, art.NIGHT)
            self._draw_product_icon(product_id, 12, y, 1)
            color = art.PAPER if selected else art.PRODUCT_ACCENTS[product_id]
            pyxel.text(22, y, product["short_name"][:8], color)
            pyxel.text(65, y, f"{product['inventory']['units']:>2}", art.PAPER)
            pyxel.text(91, y, f"{product['unit_cost_today']:>2}", art.STEEL)
            order_color = art.AMBER if selected and self.plan_orders[product_id] else art.PAPER
            pyxel.text(115, y, f"<{self.plan_orders[product_id]:02}>", order_color)
            pyxel.text(149, y, f"{self.plan_prices[product_id]:>2}", art.MAGENTA if selected else art.PAPER)
            forecast = self.game.demand_forecast(
                product_id,
                price=self.plan_prices[product_id],
                campaign_id=self.campaign_ids[self.campaign_index],
            )
            pyxel.text(176, y, f"{forecast['low']}-{forecast['high']}", art.MINT)
            life = product["shelf_life"]
            if life is not None:
                life_color = art.ORANGE if life <= 3 else art.MUTED
                pyxel.text(22, y + 8, f"{life}D LIFE", life_color)
            else:
                pyxel.text(22, y + 8, "STABLE", art.MOSS)

        try:
            quote = self.game.quote_action(self._action())
            plan_error: str | None = None
        except InvalidAction as exc:
            quote = None
            plan_error = str(exc)
        self._draw_plan_sidebar(observation, quote, plan_error)
        selected_id = self.product_ids[self.selected_product]
        selected = observation["products"][selected_id]
        art.panel(5, 193, 310, 42, accent=art.PRODUCT_ACCENTS[selected_id], fill=art.INK)
        pyxel.text(10, 197, selected["name"].upper(), art.PRODUCT_ACCENTS[selected_id])
        pyxel.text(72, 197, _clip(selected["description"], 58), art.PAPER)
        pyxel.text(10, 207, "TAGS " + _join_tags(selected["tags"], 26), art.MUTED)
        art.keycap(152, 204, "UP/DN", "PICK", color=art.CYAN)
        art.keycap(210, 204, "<>", "LOAD", color=art.AMBER)
        art.keycap(263, 204, "Z/X", "ASK", color=art.MAGENTA)
        art.keycap(10, 217, "C", "AD", color=art.MAGENTA)
        art.keycap(43, 217, "U", "TECH", color=art.CYAN)
        if plan_error:
            art.keycap(93, 217, "SPACE", "BLOCKED", color=art.SLATE, label_color=art.DANGER)
        else:
            art.keycap(93, 217, "SPACE", "OPEN MARKET", color=art.AMBER)
        if self.toast and pyxel.frame_count < self.toast_until:
            pyxel.rect(190, 218, 121, 8, art.INK)
            pyxel.text(193, 219, _clip(self.toast, 28), self.toast_color)
        else:
            tips = self.game.content["tutorial_tips"]
            tip = tips[(self.game.state["day"] - 1) % len(tips)]
            pyxel.text(190, 219, _clip("TIP " + tip, 30), art.MUTED)

    def _draw_plan_sidebar(
        self,
        observation: dict[str, Any],
        quote: dict[str, Any] | None,
        plan_error: str | None,
    ) -> None:
        art.panel(218, 59, 97, 130, title="STRATEGY", accent=art.MAGENTA)
        if quote is not None:
            art.inset(222, 73, 89, 32, color=art.SLATE)
            art.icon("credit", 226, 78, art.AMBER)
            pyxel.text(236, 76, f"SPEND {_money(quote['total_spend'])}", art.AMBER)
            left = self.game.state["cash"] - quote["total_spend"]
            pyxel.text(236, 85, f"SAFE  {_money(left)}", art.MINT if left >= 0 else art.DANGER)
            art.bar(
                226,
                95,
                79,
                quote["projected_units"],
                quote["projected_capacity"],
                color=art.CYAN,
                danger_at=0.95,
            )
        else:
            art.inset(222, 73, 89, 32, color=art.DANGER)
            pyxel.text(226, 77, "PLAN BLOCKED", art.DANGER)
            for line_index, line in enumerate(_wrap(plan_error or "", 20)[:2]):
                pyxel.text(226, 87 + line_index * 7, line, art.PEACH)

        campaign_id = self.campaign_ids[self.campaign_index]
        art.inset(222, 109, 89, 31, color=art.MAGENTA)
        art.icon("campaign", 226, 114, art.MAGENTA)
        pyxel.text(237, 112, "CAMPAIGN [C]", art.MUTED)
        if campaign_id:
            campaign = self.game.campaigns[campaign_id]
            pyxel.text(226, 122, campaign["name"][:20].upper(), art.MAGENTA)
            pyxel.text(226, 131, f"{_money(campaign['cost'])}  +{campaign['demand_bonus']} TRAFFIC", art.PAPER)
        else:
            pyxel.text(226, 124, "NO CAMPAIGN", art.MUTED)

        upgrade_id = self.upgrade_ids[self.upgrade_index]
        art.inset(222, 144, 89, 39, color=art.CYAN)
        art.icon("upgrade", 226, 149, art.CYAN)
        pyxel.text(237, 147, "UPGRADE [U]", art.MUTED)
        if upgrade_id:
            upgrade = self.game.upgrades[upgrade_id]
            level = self.game.state["upgrade_levels"][upgrade_id]
            pyxel.text(226, 157, upgrade["name"][:20].upper(), art.CYAN)
            pyxel.text(226, 166, f"LV {level}/{upgrade['max_level']}  {_money(self.game.upgrade_cost(upgrade_id))}", art.PAPER)
            pyxel.text(226, 175, _clip(upgrade["description"], 21), art.MUTED)
        else:
            pyxel.text(226, 159, "NO UPGRADE", art.MUTED)
            pyxel.text(226, 170, "SAVE YOUR CREDITS", art.STEEL)

    def _draw_product_icon(self, product_id: str, x: int, y: int, scale: int = 1) -> None:
        art.product(product_id, x, y, scale, frame=pyxel.frame_count // 8)

    def _draw_market_scene(self) -> None:
        frame = pyxel.frame_count
        pyxel.rect(10, 57, 300, 100, art.NIGHT)
        pyxel.line(10, 157, 310, 157, art.CYAN)
        art.stall(49, 68, 222, frame=frame)
        for index, product_id in enumerate(self.product_ids):
            x = 70 + index * 37
            self._draw_product_icon(product_id, x, 94, 2)
        art.vendor(151, 83, 2, frame=frame, wave=True)
        # Six customer archetypes move at distinct speeds and depths.
        for index in range(6):
            x = 12 + ((index * 57 + frame * (1 + index % 2) // 4) % 298)
            y = 127 + (index % 2) * 8
            art.customer(index, x, y, frame=frame + index * 3)
        # Animated checkout credits reinforce that this is a living market.
        for index in range(2):
            coin_x = 137 + ((frame + index * 11) % 34)
            coin_y = 121 - ((frame + index * 9) % 24)
            pyxel.pset(coin_x, coin_y, art.AMBER)

    def _draw_report(self) -> None:
        assert self.report is not None
        self._draw_header(day_override=self.report["day"])
        banner_color = art.MINT if self.report["profit"] >= 0 else art.DANGER
        art.panel(51, 26, 218, 28, accent=banner_color, fill=art.INK)
        pyxel.text(113, 30, f"NIGHT {self.report['day']:02} CLOSED", banner_color)
        if self.report["achievements"]:
            milestone = self.report["achievements"][0]
            art.icon("medal", 68, 41, art.AMBER)
            pyxel.text(79, 41, ("MILESTONE  " + milestone["name"].upper())[:44], art.AMBER)
        elif self.report.get("campaign_backfire"):
            art.icon("campaign", 68, 41, art.DANGER)
            pyxel.text(79, 41, "AD BACKFIRE  THE CROWD TURNS", art.DANGER)
        else:
            pyxel.text(71, 41, _clip(self.report["flavor"], 44), art.PAPER)
        self._draw_market_scene()

        art.panel(5, 160, 310, 75, title="NIGHT LEDGER", accent=banner_color)
        profit_color = art.MINT if self.report["profit"] >= 0 else art.DANGER
        cards = (
            (9, "credit", "SALES", _money(self.report["revenue"]), art.AMBER),
            (84, "people", "SOLD", f"{self.report['units_sold']}/{self.report['demand']}", art.PAPER),
            (159, "waste", "WASTE", str(self.report["units_spoiled"]), art.DANGER if self.report["units_spoiled"] else art.STEEL),
            (234, "profit", "PROFIT", _money(self.report["profit"]), profit_color),
        )
        for x, icon_name, label, value, color in cards:
            art.inset(x, 174, 70, 20, color=color)
            art.metric(x + 4, 177, label, value, icon_name=icon_name, color=color)
        pyxel.text(11, 198, f"SUPPLY {_money(self.report['procurement'])}", art.STEEL)
        pyxel.text(76, 198, f"RENT {_money(self.report['rent'])}", art.STEEL)
        pyxel.text(134, 198, f"REP {self.report['reputation_delta']:+.1f}", art.MAGENTA)
        pyxel.text(198, 198, f"CASH {_money(self.report['cash_after'])}", art.AMBER)

        for index, product_id in enumerate(self.product_ids):
            result = self.report["products"][product_id]
            x = 12 + index * 58
            self._draw_product_icon(product_id, x, 207, 1)
            color = art.DANGER if result["stockout"] else art.MINT
            label = f"{result['sold']}/{result['demand']}"
            if result["stockout"]:
                label += " OUT"
            pyxel.text(x + 11, 209, label, color)
            art.bar(x + 11, 217, 29, result["sold"], max(1, result["demand"]), color=color)
        prompt = "SPACE: FINAL SCORE" if self.game.state["done"] else "SPACE: PLAN NEXT NIGHT"
        prompt_x = WIDTH - len(prompt) * 4 - 10
        pyxel.text(prompt_x, 225, prompt, art.CYAN if (pyxel.frame_count // 15) % 2 else art.PAPER)

    def _draw_game_over(self) -> None:
        terminal = self.game.terminal_summary()
        rank_color = art.DANGER if terminal["rank"] == "SPACE DEBRIS" else art.AMBER
        pulse = rank_color if (pyxel.frame_count // 12) % 2 else art.PAPER
        art.panel(14, 17, 292, 216, title="SEASON COMPLETE", accent=rank_color)
        pyxel.text(225, 22, f"SEED {self.seed:04}", art.MUTED)

        art.inset(24, 35, 94, 135, color=rank_color)
        art.rank_badge(55, 43, color=rank_color, scale=2)
        rank_x = max(28, 71 - len(terminal["rank"]) * 2)
        pyxel.text(rank_x, 95, terminal["rank"], pulse)
        pyxel.text(51, 106, f"SCORE {terminal['score']}", art.PAPER)
        art.vendor(56, 119, 2, frame=pyxel.frame_count, wave=True)

        art.inset(124, 35, 168, 135, color=art.CYAN)
        pyxel.text(132, 42, "FINAL LEDGER", art.CYAN)
        pyxel.line(132, 51, 284, 51, art.SLATE)
        totals = terminal["totals"]
        rows = (
            ("CASH ON HAND", _money(terminal["cash"]), art.AMBER),
            ("LIFETIME SALES", _money(totals["revenue"]), art.MINT),
            ("UNITS SOLD", str(totals["units_sold"]), art.PAPER),
            ("STOCKOUTS", str(totals["stockouts"]), art.DANGER),
            ("SPOILED", str(totals["units_spoiled"]), art.ORANGE),
            ("UPGRADE LEVELS", str(terminal["upgrade_levels"]), art.CYAN),
        )
        for index, (label, value, color) in enumerate(rows):
            y = 58 + index * 16
            pyxel.text(132, y, label, art.MUTED)
            pyxel.text(279 - len(value) * 4, y, value, color)
            pyxel.line(132, y + 8, 283, y + 8, art.NIGHT)

        art.inset(24, 176, 268, 27, color=art.MAGENTA)
        art.icon("medal", 31, 182, art.AMBER)
        pyxel.text(42, 179, "MILESTONES", art.MUTED)
        completed = terminal["achievements_completed"]
        total = terminal["achievements_total"]
        pyxel.text(42, 188, f"{completed}/{total}", art.AMBER)
        art.bar(66, 190, 62, completed, total, color=art.AMBER)
        art.icon("rep", 143, 182, art.MAGENTA)
        pyxel.text(154, 179, "REPUTATION", art.MUTED)
        pyxel.text(154, 188, f"{terminal['reputation']:.1f}", art.MAGENTA)
        art.bar(183, 190, 98, terminal["reputation"], 100, color=art.MAGENTA)

        # Deterministic confetti gives capture mode the same celebratory feel
        # as an interactively reached ending.
        for index in range(18):
            x = (index * 47 + self.seed * 13) % WIDTH
            y = 10 + (index * 31 + pyxel.frame_count // 3) % 196
            color = (art.CYAN, art.MAGENTA, art.AMBER, art.MINT)[index % 4]
            pyxel.pset(x, y, color)
        pyxel.text(49, 208, terminal["flavor"][:52], art.STEEL)
        art.keycap(72, 219, "R", "NEW SEED", color=art.AMBER)
        art.keycap(177, 219, "T", "TITLE", color=art.CYAN)

    def _draw_help(self) -> None:
        pyxel.rect(0, 0, WIDTH, HEIGHT, art.INK)
        art.panel(9, 9, 302, 222, title="FIELD GUIDE // M0X-7", accent=art.CYAN)
        art.chip(194, 14, "1 BASICS", color=art.CYAN, active=self.help_page == 0)
        art.chip(239, 14, "2 TACTICS", color=art.MAGENTA, active=self.help_page == 1)
        if self.help_page == 0:
            steps = (
                ("1", "READ THE PORT", "Event + crowd reveal today's demand.", "signal", art.MAGENTA),
                ("2", "BUILD THE LOAD", "Buy stock, set asking prices, stay liquid.", "cargo", art.CYAN),
                ("3", "OPEN THE STALL", "Sales resolve from the shared rule core.", "profit", art.AMBER),
            )
            for index, (number, title, body, icon_name, color) in enumerate(steps):
                y = 38 + index * 43
                art.inset(21, y, 278, 35, color=color)
                art.chip(27, y + 7, number, color=color)
                art.icon(icon_name, 48, y + 8, color)
                pyxel.text(62, y + 6, title, color)
                pyxel.text(62, y + 17, body, art.PAPER)

            art.inset(21, 169, 278, 40, color=art.SLATE)
            pyxel.text(28, 174, "CONTROLS", art.MUTED)
            art.keycap(28, 185, "UP/DN", "PICK", color=art.CYAN)
            art.keycap(91, 185, "<>", "LOAD", color=art.AMBER)
            art.keycap(143, 185, "Z/X", "ASK", color=art.MAGENTA)
            art.keycap(199, 185, "C", "AD", color=art.MAGENTA)
            art.keycap(234, 185, "U", "TECH", color=art.CYAN)
            pyxel.text(28, 199, "SPACE OPEN/CONTINUE    H CLOSE GUIDE", art.STEEL)
        else:
            secrets = (
                ("PRICE", "Sensitive crowds punish greedy markups.", art.MAGENTA),
                ("FRESH", "Perishables pay fast, then become waste.", art.ORANGE),
                ("TAGS", "Match preferred tags before buying deep.", art.CYAN),
                ("BUFFER", "Keep credits for rent and supply shocks.", art.AMBER),
                ("UPGRADES", "Storage, insight, brand, automation.", art.MINT),
                ("FORECAST", "The range updates at your current ask.", art.STEEL),
            )
            for index, (title, body, color) in enumerate(secrets):
                column = index % 2
                row = index // 2
                x = 21 + column * 141
                y = 39 + row * 45
                art.inset(x, y, 136, 37, color=color)
                pyxel.text(x + 7, y + 6, title, color)
                for line_index, line in enumerate(_wrap(body, 29)[:2]):
                    pyxel.text(x + 7, y + 17 + line_index * 7, line, art.PAPER)
            art.inset(21, 180, 277, 28, color=art.PLUM)
            pyxel.text(28, 185, "AGENT BAY", art.MAGENTA)
            pyxel.text(28, 196, "agent_cli: schema // serve // autoplay", art.PAPER)
        pyxel.text(80, 218, "LEFT/RIGHT  CHANGE PAGE", art.STEEL)
        art.chip(251, 215, "H CLOSE", color=art.CYAN, active=False)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Play Starport Market in Pyxel.")
    parser.add_argument("--seed", type=int, default=7, help="Deterministic market seed.")
    parser.add_argument(
        "--screen",
        choices=("title", "plan", "report", "game_over", "help", "help_tactics"),
        default="title",
        help="Initial screen (useful for deterministic captures).",
    )
    parser.add_argument("--capture", help=argparse.SUPPRESS)
    return parser


def main(argv: list[str] | None = None) -> None:
    args = build_parser().parse_args(argv)
    GameApp(seed=args.seed, start_screen=args.screen, capture_path=args.capture)


if __name__ == "__main__":
    main()
