"""Pyxel presentation layer for human players."""

from __future__ import annotations

import argparse
import math
import random
from typing import Any

import pyxel

from .core import InvalidAction, MarketGame
from .bot import HeuristicAgent


WIDTH = 320
HEIGHT = 240


def _money(value: int) -> str:
    return f"${value}"


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
        self.capture_path = capture_path
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

    def _pressed(self, key: int, repeat: bool = False) -> bool:
        return pyxel.btnp(key, 12, 3) if repeat else pyxel.btnp(key)

    def update(self) -> None:
        if self.capture_path and pyxel.frame_count >= 2:
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
            self.mode = "plan"
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
        self.mode = "report"
        self._spawn_sparkles(max(4, min(22, self.report["units_sold"] // 2)))
        self._play_sound(0 if self.report["profit"] >= 0 else 2)

    def _update_report(self) -> None:
        if self._pressed(pyxel.KEY_SPACE) or self._pressed(pyxel.KEY_RETURN):
            if self.game.state["done"]:
                self.mode = "game_over"
                self._spawn_sparkles(40)
                self._play_sound(3)
            else:
                self._reset_plan()
                self.mode = "plan"
                self._play_sound(1)

    def _update_game_over(self) -> None:
        if self._pressed(pyxel.KEY_R):
            self.seed += 1
            self.game = MarketGame(seed=self.seed)
            self.report = None
            self._reset_plan()
            self.mode = "plan"
            self._play_sound(0)
        elif self._pressed(pyxel.KEY_T):
            self.game = MarketGame(seed=self.seed)
            self.report = None
            self._reset_plan()
            self.mode = "title"

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

    def _draw_space(self) -> None:
        pyxel.cls(1)
        frame = pyxel.frame_count
        for x, y, color, speed in self.stars:
            sy = (y + frame // (4 // speed)) % HEIGHT
            pyxel.pset(x, sy, color if (frame + x) % 20 else 7)
        pyxel.rect(0, 202, WIDTH, 38, 0)
        for x in range(0, WIDTH, 16):
            height = 8 + ((x * 7) % 22)
            pyxel.rect(x, 202 - height, 13, height, 5)
            if (x // 16 + frame // 30) % 3 == 0:
                pyxel.pset(x + 3, 198 - height, 10)

    @staticmethod
    def _panel(x: int, y: int, w: int, h: int, title: str | None = None, color: int = 5) -> None:
        pyxel.rect(x, y, w, h, 0)
        pyxel.rectb(x, y, w, h, color)
        if title:
            pyxel.rect(x + 1, y + 1, w - 2, 10, 1)
            pyxel.text(x + 5, y + 3, title, 12)

    def _draw_title(self) -> None:
        pulse = 10 if (pyxel.frame_count // 15) % 2 else 9
        pyxel.rect(34, 35, 252, 91, 0)
        pyxel.rectb(34, 35, 252, 91, 12)
        pyxel.rectb(37, 38, 246, 85, 5)
        pyxel.text(75, 51, "S T A R P O R T", 6)
        pyxel.text(88, 70, "M A R K E T", pulse)
        pyxel.line(66, 84, 254, 84, 12)
        pyxel.text(76, 94, "18 NIGHTS. ONE NEON EMPIRE.", 7)
        self._draw_vendor(151, 130, 2)
        pyxel.text(99, 178, "[SPACE] OPEN YOUR STALL", pulse)
        pyxel.text(121, 190, "[H] HOW TO PLAY", 6)
        pyxel.text(113, 217, "HUMAN + AGENT EDITION", 5)

    @staticmethod
    def _draw_vendor(x: int, y: int, scale: int = 1) -> None:
        pyxel.rect(x, y, 9 * scale, 8 * scale, 13)
        pyxel.rectb(x, y, 9 * scale, 8 * scale, 7)
        pyxel.pset(x + 2 * scale, y + 3 * scale, 12)
        pyxel.pset(x + 6 * scale, y + 3 * scale, 12)
        pyxel.rect(x + 2 * scale, y + 8 * scale, 5 * scale, 5 * scale, 6)
        pyxel.line(x - 2 * scale, y + 10 * scale, x + 2 * scale, y + 9 * scale, 6)
        pyxel.line(x + 7 * scale, y + 9 * scale, x + 11 * scale, y + 7 * scale, 6)
        pyxel.pset(x + 11 * scale, y + 6 * scale, 10)

    def _draw_header(self, day_override: int | None = None) -> None:
        pyxel.rect(0, 0, WIDTH, 20, 0)
        pyxel.line(0, 19, WIDTH, 19, 12)
        day = self.game.state["day"] if day_override is None else day_override
        pyxel.text(7, 6, f"DAY {day:02}/{self.game.state['total_days']}", 7)
        pyxel.text(75, 6, f"CASH {_money(self.game.state['cash'])}", 10)
        pyxel.text(153, 6, f"REP {self.game.state['reputation']:.0f}", 14)
        used = self.game.inventory_count()
        capacity = self.game.capacity()
        pyxel.text(217, 6, f"HOLD {used}/{capacity}", 6)
        pyxel.text(296, 6, "H?", 5)

    def _draw_plan(self) -> None:
        self._draw_header()
        observation = self.game.observation()
        event = observation["market"]["event"]
        group = observation["market"]["customer_group"]
        self._panel(5, 24, 310, 32)
        pyxel.text(10, 28, event["name"].upper(), 14)
        pyxel.text(111, 28, event["headline"][:47], 7)
        pyxel.text(10, 40, f"CROWD: {group['name'].upper()}", 12)
        pyxel.text(111, 40, "LIKES " + "/".join(group["preferred_tags"])[:37], 6)

        self._panel(5, 60, 207, 132, "INVENTORY / DAY PLAN")
        pyxel.text(11, 74, "ITEM       HAVE COST  BUY PRICE FCST", 5)
        for index, product_id in enumerate(self.product_ids):
            product = observation["products"][product_id]
            y = 85 + index * 20
            selected = index == self.selected_product
            if selected:
                pyxel.rect(7, y - 3, 203, 18, 5)
                pyxel.rectb(7, y - 3, 203, 18, 12)
            self._draw_product_icon(product_id, 11, y - 1, 1)
            color = 7 if selected else int(self.game.products[product_id]["color"])
            pyxel.text(22, y, product["short_name"][:8], color)
            pyxel.text(67, y, f"{product['inventory']['units']:>3}", 7)
            pyxel.text(91, y, f"{product['unit_cost_today']:>3}", 6)
            pyxel.text(116, y, f"<{self.plan_orders[product_id]:>2}>", 10 if selected else 7)
            pyxel.text(147, y, f"{self.plan_prices[product_id]:>3}", 14 if selected else 7)
            forecast = self.game.demand_forecast(
                product_id,
                price=self.plan_prices[product_id],
                campaign_id=self.campaign_ids[self.campaign_index],
            )
            pyxel.text(174, y, f"{forecast['low']}-{forecast['high']}", 11)
            life = product["shelf_life"]
            if life is not None:
                pyxel.text(22, y + 7, f"life {life}d", 13 if life <= 3 else 5)

        self._draw_plan_sidebar(observation)
        selected_id = self.product_ids[self.selected_product]
        selected = observation["products"][selected_id]
        pyxel.rect(5, 196, 310, 39, 0)
        pyxel.rectb(5, 196, 310, 39, 5)
        pyxel.text(10, 201, selected["description"][:58], 7)
        pyxel.text(10, 211, "UP/DOWN item  LEFT/RIGHT buy  Z/X price", 6)
        pyxel.text(10, 220, "C campaign  U upgrade  SPACE open market", 12)
        if self.toast and pyxel.frame_count < self.toast_until:
            pyxel.rect(8, 229, 304, 8, 0)
            pyxel.text(10, 230, self.toast[:74], self.toast_color)
        else:
            tips = self.game.content["tutorial_tips"]
            tip = tips[(self.game.state["day"] - 1) % len(tips)]
            pyxel.text(10, 230, "TIP: " + tip[:70], 5)

    def _draw_plan_sidebar(self, observation: dict[str, Any]) -> None:
        self._panel(216, 60, 99, 132, "STRATEGY")
        action = self._action()
        try:
            quote = self.game.quote_action(action)
            pyxel.text(222, 75, f"SPEND {_money(quote['total_spend'])}", 10)
            pyxel.text(222, 84, f"LEFT  {_money(self.game.state['cash'] - quote['total_spend'])}", 11)
            pyxel.text(222, 93, f"SLOTS {quote['projected_units']}/{quote['projected_capacity']}", 6)
        except InvalidAction as exc:
            pyxel.text(222, 75, "PLAN INVALID", 8)
            for line_index, line in enumerate(_wrap(str(exc), 22)[:3]):
                pyxel.text(222, 85 + line_index * 7, line, 8)

        campaign_id = self.campaign_ids[self.campaign_index]
        pyxel.text(222, 110, "CAMPAIGN [C]", 5)
        if campaign_id:
            campaign = self.game.campaigns[campaign_id]
            pyxel.text(222, 120, campaign["name"][:21], 14)
            pyxel.text(222, 129, f"cost {_money(campaign['cost'])}  +{campaign['demand_bonus']} buzz", 7)
        else:
            pyxel.text(222, 120, "None", 13)

        upgrade_id = self.upgrade_ids[self.upgrade_index]
        pyxel.text(222, 145, "UPGRADE [U]", 5)
        if upgrade_id:
            upgrade = self.game.upgrades[upgrade_id]
            level = self.game.state["upgrade_levels"][upgrade_id]
            pyxel.text(222, 155, upgrade["name"][:21], 12)
            pyxel.text(222, 164, f"Lv {level}/{upgrade['max_level']}  {_money(self.game.upgrade_cost(upgrade_id))}", 7)
            for index, line in enumerate(_wrap(upgrade["description"], 22)[:2]):
                pyxel.text(222, 174 + index * 7, line, 6)
        else:
            pyxel.text(222, 155, "None", 13)

    def _draw_product_icon(self, product_id: str, x: int, y: int, scale: int = 1) -> None:
        if product_id == "glow_noodles":
            pyxel.rect(x, y + 5 * scale, 8 * scale, 3 * scale, 4)
            pyxel.line(x + scale, y + 4 * scale, x + 7 * scale, y + 4 * scale, 10)
            pyxel.pset(x + 2 * scale, y + 2 * scale, 10)
            pyxel.pset(x + 5 * scale, y + scale, 10)
        elif product_id == "plasma_fruit":
            pyxel.circ(x + 4 * scale, y + 4 * scale, 3 * scale, 14)
            pyxel.line(x + 4 * scale, y + scale, x + 6 * scale, y, 11)
        elif product_id == "void_tea":
            pyxel.rectb(x + scale, y + 2 * scale, 6 * scale, 6 * scale, 2)
            pyxel.line(x + 7 * scale, y + 4 * scale, x + 8 * scale, y + 5 * scale, 6)
        elif product_id == "meteor_jerky":
            pyxel.line(x, y + 6 * scale, x + 7 * scale, y + 2 * scale, 4)
            pyxel.line(x + scale, y + 7 * scale, x + 8 * scale, y + 3 * scale, 9)
        else:
            pyxel.rectb(x + scale, y + scale, 7 * scale, 7 * scale, 12)
            pyxel.pset(x + 4 * scale, y + 4 * scale, 14)

    def _draw_market_scene(self) -> None:
        pyxel.rect(18, 58, 284, 87, 0)
        pyxel.rectb(18, 58, 284, 87, 12)
        pyxel.rect(31, 74, 258, 58, 5)
        pyxel.rect(40, 84, 240, 40, 1)
        for index, product_id in enumerate(self.product_ids):
            x = 53 + index * 46
            self._draw_product_icon(product_id, x, 95, 2)
            pyxel.rect(x - 6, 115, 30, 6, 4)
        self._draw_vendor(152, 118, 1)
        frame = pyxel.frame_count
        for index in range(7):
            x = 28 + ((index * 47 + frame // 3) % 270)
            y = 148 + (index % 2) * 8
            color = (index * 2 + 6) % 15 or 7
            pyxel.circ(x, y, 3, color)
            pyxel.rect(x - 2, y + 3, 5, 6, color)

    def _draw_report(self) -> None:
        assert self.report is not None
        self._draw_header(day_override=self.report["day"])
        self._draw_market_scene()
        pyxel.rect(40, 26, 240, 25, 0)
        pyxel.rectb(40, 26, 240, 25, 14)
        pyxel.text(112, 31, f"DAY {self.report['day']} CLOSED", 14)
        if self.report["achievements"]:
            milestone = self.report["achievements"][0]
            pyxel.text(70, 41, ("MILESTONE: " + milestone["name"])[:46], 10)
        else:
            pyxel.text(72, 41, self.report["flavor"][:45], 7)

        self._panel(5, 164, 310, 69, "NIGHT LEDGER")
        profit_color = 11 if self.report["profit"] >= 0 else 8
        pyxel.text(11, 178, f"SALES {_money(self.report['revenue'])}", 10)
        pyxel.text(78, 178, f"SOLD {self.report['units_sold']}/{self.report['demand']}", 7)
        pyxel.text(151, 178, f"WASTE {self.report['units_spoiled']}", 8 if self.report["units_spoiled"] else 6)
        pyxel.text(215, 178, f"PROFIT {_money(self.report['profit'])}", profit_color)
        pyxel.text(11, 189, f"SUPPLY {_money(self.report['procurement'])}", 6)
        pyxel.text(78, 189, f"RENT {_money(self.report['rent'])}", 6)
        pyxel.text(143, 189, f"REP {self.report['reputation_delta']:+.1f}", 14)
        pyxel.text(215, 189, f"CASH {_money(self.report['cash_after'])}", 10)

        x = 11
        for product_id in self.product_ids:
            result = self.report["products"][product_id]
            self._draw_product_icon(product_id, x, 202, 1)
            color = 8 if result["stockout"] else 11
            pyxel.text(x + 10, 204, f"{result['sold']}/{result['demand']}", color)
            x += 58
        prompt = "SPACE: FINAL SCORE" if self.game.state["done"] else "SPACE: PLAN NEXT NIGHT"
        pyxel.text(111, 222, prompt, 12 if (pyxel.frame_count // 15) % 2 else 7)

    def _draw_game_over(self) -> None:
        terminal = self.game.terminal_summary()
        pulse = 10 if (pyxel.frame_count // 12) % 2 else 14
        pyxel.rect(28, 27, 264, 184, 0)
        pyxel.rectb(28, 27, 264, 184, 12)
        pyxel.rectb(31, 30, 258, 178, 5)
        pyxel.text(119, 42, "FINAL LEDGER", 6)
        rank_x = max(45, 160 - len(terminal["rank"]) * 2)
        pyxel.text(rank_x, 62, terminal["rank"], pulse)
        pyxel.text(123, 78, f"SCORE {terminal['score']}", 7)
        pyxel.line(65, 91, 255, 91, 5)
        totals = terminal["totals"]
        pyxel.text(65, 104, f"Cash on hand     {_money(terminal['cash']):>8}", 10)
        pyxel.text(65, 116, f"Lifetime sales   {_money(totals['revenue']):>8}", 11)
        pyxel.text(65, 128, f"Units sold       {totals['units_sold']:>8}", 7)
        pyxel.text(65, 140, f"Stockouts        {totals['stockouts']:>8}", 8)
        pyxel.text(65, 152, f"Spoiled          {totals['units_spoiled']:>8}", 13)
        pyxel.text(65, 164, f"Reputation       {terminal['reputation']:>8.1f}", 14)
        pyxel.text(65, 176, f"Milestones       {terminal['achievements_completed']:>5}/{terminal['achievements_total']}", 10)
        pyxel.text(65, 188, terminal["flavor"][:47], 6)
        pyxel.text(75, 201, "[R] NEW SEED     [T] TITLE", 12)

    def _draw_help(self) -> None:
        pyxel.rect(8, 8, 304, 224, 0)
        pyxel.rectb(8, 8, 304, 224, 12)
        pyxel.rectb(11, 11, 298, 218, 5)
        if self.help_page == 0:
            pyxel.text(121, 20, "HOW TO TRADE", 14)
            lines = [
                "You have 18 nights to build a neon market.",
                "Each day reveals an EVENT and a CUSTOMER CROWD.",
                "Match product tags to demand, then set stock + price.",
                "Fresh goods expire. Unsold waste costs cash and rep.",
                "Campaigns create demand; upgrades shape your strategy.",
                "The same deterministic rules power human + agent play.",
                "",
                "UP / DOWN       Select a product",
                "LEFT / RIGHT    Buy fewer / more units",
                "Z / X           Lower / raise price",
                "C               Cycle marketing campaign",
                "U               Cycle permanent upgrade",
                "SPACE / ENTER   Open market / continue",
                "H               Open or close this guide",
            ]
        else:
            pyxel.text(115, 20, "MARKET SECRETS", 14)
            lines = [
                "FORECAST is a range at today's current price.",
                "Price-sensitive crowds punish greedy markups.",
                "Preferred tags raise demand before event effects.",
                "Noodles + fruit spoil; jerky + charms never do.",
                "Insight upgrades reveal future crowds and events.",
                "Brand grows demand; storage enables event stockpiles.",
                "Automation cuts supply costs and rent.",
                "Keep cash for rent and sudden supply shocks.",
                "",
                "AGENTS: run  python -m starport_market.agent_cli",
                "Use `schema`, `serve`, or `autoplay` subcommands.",
                "JSON observations expose every decision-relevant rule.",
            ]
        for index, line in enumerate(lines):
            color = 12 if line.startswith(("UP", "LEFT", "Z ", "C ", "U ", "SPACE", "H ", "AGENTS")) else 7
            pyxel.text(23, 39 + index * 11, line, color)
        pyxel.text(103, 215, "LEFT/RIGHT PAGE   H CLOSE", 6)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Play Starport Market in Pyxel.")
    parser.add_argument("--seed", type=int, default=7, help="Deterministic market seed.")
    parser.add_argument(
        "--screen",
        choices=("title", "plan", "report", "game_over"),
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
