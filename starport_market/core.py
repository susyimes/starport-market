"""Deterministic economy shared by the Pyxel UI and JSON agents."""

from __future__ import annotations

import copy
import hashlib
import json
import math
import random
from typing import Any

from .content import load_content


TOTAL_DAYS = 18
START_CASH = 120
START_REPUTATION = 50.0
BASE_CAPACITY = 24
BASE_RENT = 6
WASTE_FEE = 1
STATE_VERSION = 1


class InvalidAction(ValueError):
    """Raised when an action is malformed or unaffordable."""


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


class MarketGame:
    """An 18-day, deterministic market-management episode.

    Every source of chance is derived from ``seed`` and ``day``. Calling
    :meth:`step` with the same state and action therefore produces identical
    results on every platform.
    """

    def __init__(
        self,
        seed: int = 7,
        *,
        state: dict[str, Any] | None = None,
        content: dict[str, Any] | None = None,
    ) -> None:
        self.content = content or load_content()
        self.products = {item["id"]: item for item in self.content["products"]}
        self.events = {item["id"]: item for item in self.content["events"]}
        self.groups = {item["id"]: item for item in self.content["customer_groups"]}
        self.upgrades = {item["id"]: item for item in self.content["upgrades"]}
        self.campaigns = {item["id"]: item for item in self.content["campaigns"]}
        self.achievements = {item["id"]: item for item in self.content["achievements"]}
        self.product_ids = tuple(self.products)
        self.state = copy.deepcopy(state) if state is not None else self._new_state(int(seed))
        self._validate_state()

    @classmethod
    def from_state(
        cls, state: dict[str, Any], *, content: dict[str, Any] | None = None
    ) -> "MarketGame":
        return cls(state=state, content=content)

    def clone(self) -> "MarketGame":
        return MarketGame.from_state(self.export_state(), content=self.content)

    def _new_state(self, seed: int) -> dict[str, Any]:
        rng = random.Random(seed ^ 0x5A17_2026)
        event_items = list(self.content["events"])
        event_weights = [max(1, int(item.get("weight", 1))) for item in event_items]
        event_schedule: list[str] = []
        for _ in range(TOTAL_DAYS):
            selected = rng.choices(event_items, weights=event_weights, k=1)[0]["id"]
            if event_schedule and selected == event_schedule[-1]:
                index = (next(i for i, item in enumerate(event_items) if item["id"] == selected) + 1) % len(event_items)
                selected = event_items[index]["id"]
            event_schedule.append(selected)

        # End on the strongest all-market event so the finale always feels busy.
        finale = max(
            event_items,
            key=lambda item: float(item.get("effects", {}).get("demand_all", 1.0)),
        )
        event_schedule[-1] = finale["id"]

        group_items = list(self.content["customer_groups"])
        group_schedule = [rng.choice(group_items)["id"] for _ in range(TOTAL_DAYS)]
        return {
            "version": STATE_VERSION,
            "seed": seed,
            "day": 1,
            "total_days": TOTAL_DAYS,
            "cash": START_CASH,
            "reputation": START_REPUTATION,
            "inventory": {product_id: [] for product_id in self.product_ids},
            "prices": {
                product_id: int(self.products[product_id]["base_price"])
                for product_id in self.product_ids
            },
            "upgrade_levels": {upgrade_id: 0 for upgrade_id in self.upgrades},
            "event_schedule": event_schedule,
            "group_schedule": group_schedule,
            "history": [],
            "completed_achievements": [],
            "stats": {
                "perfect_service_days": 0,
                "no_waste_days": 0,
                "campaign_days": 0,
            },
            "totals": {
                "revenue": 0,
                "procurement": 0,
                "rent": 0,
                "campaigns": 0,
                "upgrades": 0,
                "waste_fees": 0,
                "units_sold": 0,
                "units_spoiled": 0,
                "stockouts": 0,
            },
            "done": False,
            "ending": None,
        }

    def _validate_state(self) -> None:
        if self.state.get("version") != STATE_VERSION:
            raise ValueError("unsupported state version")
        if set(self.state.get("inventory", {})) != set(self.product_ids):
            raise ValueError("state inventory does not match content products")
        if len(self.state.get("event_schedule", [])) != self.state["total_days"]:
            raise ValueError("invalid event schedule")
        if len(self.state.get("group_schedule", [])) != self.state["total_days"]:
            raise ValueError("invalid customer schedule")

    def export_state(self) -> dict[str, Any]:
        return copy.deepcopy(self.state)

    def state_digest(self) -> str:
        payload = json.dumps(
            self.state, sort_keys=True, separators=(",", ":"), ensure_ascii=True
        ).encode("utf-8")
        return hashlib.sha256(payload).hexdigest()

    def _day_index(self, day: int | None = None) -> int:
        selected_day = self.state["day"] if day is None else day
        return max(0, min(self.state["total_days"] - 1, selected_day - 1))

    def event_at(self, day: int | None = None) -> dict[str, Any]:
        return self.events[self.state["event_schedule"][self._day_index(day)]]

    def group_at(self, day: int | None = None) -> dict[str, Any]:
        return self.groups[self.state["group_schedule"][self._day_index(day)]]

    def _stable_random(self, label: str, day: int | None = None) -> random.Random:
        selected_day = self.state["day"] if day is None else day
        payload = f"{self.state['seed']}:{selected_day}:{label}".encode("utf-8")
        seed = int.from_bytes(hashlib.sha256(payload).digest()[:8], "big")
        return random.Random(seed)

    def inventory_count(self, product_id: str | None = None) -> int:
        if product_id is not None:
            return sum(int(batch["quantity"]) for batch in self.state["inventory"][product_id])
        return sum(self.inventory_count(item_id) for item_id in self.product_ids)

    def _levels_with(self, upgrade_id: str | None = None) -> dict[str, int]:
        levels = dict(self.state["upgrade_levels"])
        if upgrade_id:
            levels[upgrade_id] += 1
        return levels

    def _effect_sum(self, key: str, levels: dict[str, int] | None = None) -> float:
        selected_levels = levels or self.state["upgrade_levels"]
        total = 0.0
        for upgrade_id, level in selected_levels.items():
            value = self.upgrades[upgrade_id].get("effects", {}).get(key)
            if isinstance(value, (int, float)):
                total += float(value) * level
        return total

    def _effect_multiplier(self, key: str, levels: dict[str, int] | None = None) -> float:
        selected_levels = levels or self.state["upgrade_levels"]
        multiplier = 1.0
        for upgrade_id, level in selected_levels.items():
            value = self.upgrades[upgrade_id].get("effects", {}).get(key)
            if isinstance(value, (int, float)):
                multiplier *= float(value) ** level
        return multiplier

    def upgrade_cost(self, upgrade_id: str) -> int:
        if upgrade_id not in self.upgrades:
            raise InvalidAction(f"unknown upgrade: {upgrade_id}")
        item = self.upgrades[upgrade_id]
        level = self.state["upgrade_levels"][upgrade_id]
        if level >= int(item["max_level"]):
            raise InvalidAction(f"upgrade already maxed: {upgrade_id}")
        return int(math.ceil(float(item["base_cost"]) * float(item["cost_growth"]) ** level))

    def capacity(
        self,
        *,
        levels: dict[str, int] | None = None,
        day: int | None = None,
    ) -> int:
        event_delta = int(self.event_at(day).get("effects", {}).get("capacity_delta", 0))
        upgrade_delta = int(round(self._effect_sum("capacity_delta", levels)))
        return max(1, BASE_CAPACITY + upgrade_delta + event_delta)

    def shelf_life(
        self, product_id: str, *, levels: dict[str, int] | None = None
    ) -> int | None:
        base = self.products[product_id].get("shelf_life")
        if base is None:
            return None
        bonus = int(round(self._effect_sum("shelf_life_bonus", levels)))
        return int(base) + bonus

    @staticmethod
    def _tag_multiplier(
        product: dict[str, Any], mapping: dict[str, Any] | None
    ) -> float:
        multiplier = 1.0
        for tag in product["tags"]:
            value = (mapping or {}).get(tag)
            if isinstance(value, (int, float)):
                multiplier *= float(value)
        return multiplier

    def unit_cost(
        self,
        product_id: str,
        *,
        levels: dict[str, int] | None = None,
        day: int | None = None,
    ) -> int:
        product = self.products[product_id]
        effects = self.event_at(day).get("effects", {})
        factor = float(effects.get("cost_all", 1.0))
        factor *= self._tag_multiplier(product, effects.get("cost_tags"))
        factor = _clamp(factor, 0.45, 2.5)
        discount = _clamp(self._effect_sum("order_discount", levels), 0.0, 0.35)
        return max(1, int(math.ceil(product["base_cost"] * factor * (1.0 - discount))))

    def price_bounds(self, product_id: str) -> tuple[int, int]:
        product = self.products[product_id]
        return max(1, int(product["base_cost"]) // 2), int(product["base_price"]) * 3

    def _normalize_action(self, action: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(action, dict):
            raise InvalidAction("action must be a JSON object")
        allowed = {"orders", "prices", "campaign", "upgrade"}
        unknown = set(action) - allowed
        if unknown:
            raise InvalidAction(f"unknown action fields: {sorted(unknown)}")

        raw_orders = action.get("orders", {})
        raw_prices = action.get("prices", {})
        if not isinstance(raw_orders, dict) or not isinstance(raw_prices, dict):
            raise InvalidAction("orders and prices must be objects")
        if set(raw_orders) - set(self.product_ids):
            raise InvalidAction("orders contains an unknown product")
        if set(raw_prices) - set(self.product_ids):
            raise InvalidAction("prices contains an unknown product")

        orders: dict[str, int] = {}
        prices: dict[str, int] = {}
        for product_id in self.product_ids:
            quantity = raw_orders.get(product_id, 0)
            price = raw_prices.get(product_id, self.state["prices"][product_id])
            if isinstance(quantity, bool) or not isinstance(quantity, int) or not 0 <= quantity <= 99:
                raise InvalidAction(f"order for {product_id} must be an integer from 0 to 99")
            if isinstance(price, bool) or not isinstance(price, int):
                raise InvalidAction(f"price for {product_id} must be an integer")
            low, high = self.price_bounds(product_id)
            if not low <= price <= high:
                raise InvalidAction(f"price for {product_id} must be between {low} and {high}")
            orders[product_id] = quantity
            prices[product_id] = price

        campaign = action.get("campaign")
        if campaign in ("", "none"):
            campaign = None
        if campaign is not None and campaign not in self.campaigns:
            raise InvalidAction(f"unknown campaign: {campaign}")

        upgrade = action.get("upgrade")
        if upgrade in ("", "none"):
            upgrade = None
        if upgrade is not None:
            self.upgrade_cost(upgrade)

        return {"orders": orders, "prices": prices, "campaign": campaign, "upgrade": upgrade}

    def quote_action(self, action: dict[str, Any]) -> dict[str, Any]:
        normalized = self._normalize_action(action)
        upgrade_id = normalized["upgrade"]
        levels = self._levels_with(upgrade_id)
        unit_costs = {
            product_id: self.unit_cost(product_id, levels=levels)
            for product_id in self.product_ids
        }
        procurement = sum(
            normalized["orders"][product_id] * unit_costs[product_id]
            for product_id in self.product_ids
        )
        upgrade_cost = self.upgrade_cost(upgrade_id) if upgrade_id else 0
        campaign_cost = int(self.campaigns[normalized["campaign"]]["cost"]) if normalized["campaign"] else 0
        total_spend = procurement + upgrade_cost + campaign_cost
        projected_units = self.inventory_count() + sum(normalized["orders"].values())
        projected_capacity = self.capacity(levels=levels)
        # A temporary event can shrink the hold below existing stock. The
        # player may still open the stall, but cannot add more units until the
        # overflow is sold or a storage upgrade is installed.
        capacity_limit = max(self.inventory_count(), projected_capacity)
        if projected_units > capacity_limit:
            raise InvalidAction(
                f"capacity exceeded: {projected_units} units planned for {projected_capacity} slots"
            )
        if total_spend > self.state["cash"]:
            raise InvalidAction(
                f"cannot afford plan: costs {total_spend}, cash is {self.state['cash']}"
            )
        demand_forecasts = {
            product_id: self.demand_forecast(
                product_id,
                price=normalized["prices"][product_id],
                campaign_id=normalized["campaign"],
                levels=levels,
            )
            for product_id in self.product_ids
        }
        estimated_revenue = {"low": 0, "mid": 0, "high": 0}
        for product_id in self.product_ids:
            available = self.inventory_count(product_id) + normalized["orders"][product_id]
            price = normalized["prices"][product_id]
            for band in estimated_revenue:
                estimated_revenue[band] += min(
                    available, demand_forecasts[product_id][band]
                ) * price
        return {
            "normalized_action": normalized,
            "unit_costs": unit_costs,
            "procurement": procurement,
            "upgrade_cost": upgrade_cost,
            "campaign_cost": campaign_cost,
            "total_spend": total_spend,
            "projected_units": projected_units,
            "projected_capacity": projected_capacity,
            "demand_forecasts": demand_forecasts,
            "estimated_revenue": estimated_revenue,
        }

    def _demand_for(
        self,
        product_id: str,
        price: int,
        *,
        day: int | None = None,
        campaign_id: str | None = None,
        include_noise: bool = True,
        levels: dict[str, int] | None = None,
    ) -> int:
        selected_day = self.state["day"] if day is None else day
        product = self.products[product_id]
        group = self.group_at(selected_day)
        effects = self.event_at(selected_day).get("effects", {})

        demand = float(product["base_demand"])
        demand *= float(effects.get("demand_all", 1.0))
        demand *= self._tag_multiplier(product, effects.get("demand_tags"))

        matching_preferences = set(product["tags"]) & set(group["preferred_tags"])
        if matching_preferences:
            demand *= 1.22 + min(0.18, 0.06 * len(matching_preferences))
        else:
            demand *= 0.9

        reputation_factor = 0.70 + float(self.state["reputation"]) / 166.67
        demand *= _clamp(reputation_factor, 0.55, 1.35)
        demand *= self._effect_multiplier("demand_all", levels)
        loyalty = self._effect_sum("loyalty_bonus", levels)
        demand *= 1.0 + min(0.25, loyalty * 0.04)

        if campaign_id:
            campaign = self.campaigns[campaign_id]
            demand += float(campaign.get("demand_bonus", 0))
            for tag in matching_preferences | set(product["tags"]):
                demand += float(campaign.get("tag_bonus", {}).get(tag, 0))

        sensitivity = float(group["price_sensitivity"])
        price_factor = (float(product["base_price"]) / max(1, price)) ** sensitivity
        demand *= _clamp(price_factor, 0.28, 2.2)
        demand += float(group.get("loyalty_bias", 0)) * 0.35

        if include_noise:
            noise = self._stable_random(f"demand:{product_id}", selected_day).uniform(0.86, 1.14)
            demand *= noise
        return max(0, int(round(demand)))

    def _sell(self, product_id: str, requested: int) -> int:
        remaining = requested
        sold = 0
        batches = self.state["inventory"][product_id]
        for batch in batches:
            take = min(int(batch["quantity"]), remaining)
            batch["quantity"] -= take
            remaining -= take
            sold += take
            if remaining <= 0:
                break
        self.state["inventory"][product_id] = [
            batch for batch in batches if batch["quantity"] > 0
        ]
        return sold

    def _age_and_spoil(self) -> dict[str, int]:
        spoiled: dict[str, int] = {}
        for product_id in self.product_ids:
            life = self.shelf_life(product_id)
            if life is None:
                spoiled[product_id] = 0
                continue
            kept: list[dict[str, int]] = []
            lost = 0
            for batch in self.state["inventory"][product_id]:
                batch["age"] += 1
                if batch["age"] >= life:
                    lost += int(batch["quantity"])
                else:
                    kept.append(batch)
            self.state["inventory"][product_id] = kept
            spoiled[product_id] = lost
        return spoiled

    def _daily_rent(self) -> int:
        base = BASE_RENT + ((self.state["day"] - 1) // 6) * 2
        discount = int(round(self._effect_sum("rent_discount")))
        return max(2, base - discount)

    def _choose_flavor(self, category: str) -> str:
        lines = self.content["flavor_lines"][category]
        rng = self._stable_random(f"flavor:{category}")
        return lines[rng.randrange(len(lines))]

    def _achievement_value(self, metric: str) -> float:
        if metric == "total_units_sold":
            return float(self.state["totals"]["units_sold"])
        if metric == "total_revenue":
            return float(self.state["totals"]["revenue"])
        if metric == "cash":
            return float(self.state["cash"])
        if metric == "reputation":
            return float(self.state["reputation"])
        if metric == "upgrade_levels":
            return float(sum(self.state["upgrade_levels"].values()))
        if metric in {"perfect_service_days", "no_waste_days", "campaign_days"}:
            return float(self.state["stats"][metric])
        if metric == "total_units_spoiled":
            return float(self.state["totals"]["units_spoiled"])
        raise ValueError(f"unknown achievement metric: {metric}")

    def _unlock_achievements(self, *, terminal_only: bool) -> list[dict[str, Any]]:
        unlocked: list[dict[str, Any]] = []
        for item in self.content["achievements"]:
            if item["id"] in self.state["completed_achievements"]:
                continue
            is_terminal = item["metric"] == "total_units_spoiled" and item["target"] == 0
            if terminal_only != is_terminal:
                continue
            value = self._achievement_value(item["metric"])
            if is_terminal:
                met = self.state["ending"] == "completed" and value == 0
            else:
                met = value >= float(item["target"])
            if not met:
                continue
            self.state["completed_achievements"].append(item["id"])
            cash_reward = int(item["cash_reward"])
            reputation_reward = int(item["reputation_reward"])
            self.state["cash"] += cash_reward
            self.state["reputation"] = round(
                _clamp(self.state["reputation"] + reputation_reward, 0.0, 100.0), 2
            )
            unlocked.append(
                {
                    "id": item["id"],
                    "name": item["name"],
                    "description": item["description"],
                    "cash_reward": cash_reward,
                    "reputation_reward": reputation_reward,
                }
            )
        return unlocked

    def step(self, action: dict[str, Any]) -> dict[str, Any]:
        if self.state["done"]:
            raise InvalidAction("episode is already over; reset before stepping")

        quote = self.quote_action(action)
        normalized = quote["normalized_action"]
        cash_before = int(self.state["cash"])
        reputation_before = float(self.state["reputation"])
        current_day = int(self.state["day"])
        event = self.event_at()
        group = self.group_at()

        upgrade_id = normalized["upgrade"]
        if upgrade_id:
            self.state["upgrade_levels"][upgrade_id] += 1
            immediate_rep = self.upgrades[upgrade_id].get("effects", {}).get("reputation_delta", 0)
            self.state["reputation"] = _clamp(
                self.state["reputation"] + float(immediate_rep), 0.0, 100.0
            )

        self.state["prices"] = dict(normalized["prices"])
        self.state["cash"] -= quote["total_spend"]
        for product_id, quantity in normalized["orders"].items():
            if quantity:
                self.state["inventory"][product_id].append({"quantity": quantity, "age": 0})

        product_results: dict[str, dict[str, Any]] = {}
        total_demand = 0
        total_sold = 0
        total_revenue = 0
        stockouts = 0
        for product_id in self.product_ids:
            price = normalized["prices"][product_id]
            demand = self._demand_for(
                product_id,
                price,
                campaign_id=normalized["campaign"],
            )
            sold = self._sell(product_id, demand)
            revenue = sold * price
            total_demand += demand
            total_sold += sold
            total_revenue += revenue
            is_stockout = demand > sold
            stockouts += int(is_stockout)
            product_results[product_id] = {
                "demand": demand,
                "sold": sold,
                "stockout": is_stockout,
                "price": price,
                "revenue": revenue,
                "remaining": self.inventory_count(product_id),
            }

        self.state["cash"] += total_revenue
        rent = self._daily_rent()
        self.state["cash"] -= rent
        spoiled = self._age_and_spoil()
        total_spoiled = sum(spoiled.values())
        for product_id in self.product_ids:
            product_results[product_id]["remaining"] = self.inventory_count(product_id)
        waste_fee = total_spoiled * WASTE_FEE
        self.state["cash"] -= waste_fee

        fulfillment = total_sold / total_demand if total_demand else 1.0
        if fulfillment >= 0.9:
            service_rep = 1.5
        elif fulfillment >= 0.7:
            service_rep = 0.5
        elif fulfillment >= 0.4:
            service_rep = -0.75
        else:
            service_rep = -2.0
        reputation_delta = service_rep
        reputation_delta += float(event.get("effects", {}).get("reputation_delta", 0))
        reputation_delta += float(group.get("loyalty_bias", 0)) * 0.15
        reputation_delta -= min(3.0, total_spoiled * 0.15)

        campaign_backfire = False
        campaign_id = normalized["campaign"]
        if campaign_id:
            risk = int(self.campaigns[campaign_id].get("reputation_risk", 0))
            if risk and self._stable_random(f"campaign:{campaign_id}").random() < 0.12 * risk:
                campaign_backfire = True
                reputation_delta -= risk + 0.5
            else:
                reputation_delta += 0.25

        self.state["reputation"] = round(
            _clamp(self.state["reputation"] + reputation_delta, 0.0, 100.0), 2
        )
        operating_profit = (
            total_revenue
            - quote["procurement"]
            - quote["campaign_cost"]
            - quote["upgrade_cost"]
            - rent
            - waste_fee
        )
        totals = self.state["totals"]
        totals["revenue"] += total_revenue
        totals["procurement"] += quote["procurement"]
        totals["campaigns"] += quote["campaign_cost"]
        totals["upgrades"] += quote["upgrade_cost"]
        totals["rent"] += rent
        totals["waste_fees"] += waste_fee
        totals["units_sold"] += total_sold
        totals["units_spoiled"] += total_spoiled
        totals["stockouts"] += stockouts

        stats = self.state["stats"]
        stats["perfect_service_days"] += int(fulfillment >= 0.98)
        stats["no_waste_days"] += int(total_spoiled == 0)
        stats["campaign_days"] += int(campaign_id is not None)
        unlocked = self._unlock_achievements(terminal_only=False)

        if current_day >= self.state["total_days"]:
            self.state["done"] = True
            self.state["ending"] = "completed"
        elif self.state["cash"] < 0 and self.inventory_count() == 0:
            self.state["done"] = True
            self.state["ending"] = "bankrupt"
        if self.state["done"]:
            unlocked.extend(self._unlock_achievements(terminal_only=True))

        achievement_cash = sum(item["cash_reward"] for item in unlocked)
        achievement_reputation = sum(item["reputation_reward"] for item in unlocked)
        actual_rep_delta = round(self.state["reputation"] - reputation_before, 2)

        if total_spoiled:
            flavor = self._choose_flavor("spoilage")
        elif stockouts >= 3:
            flavor = self._choose_flavor("stockout")
        elif upgrade_id:
            flavor = self._choose_flavor("upgrade")
        else:
            flavor = self._choose_flavor("sale_success")

        report: dict[str, Any] = {
            "day": current_day,
            "event": event["id"],
            "event_name": event["name"],
            "customer_group": group["id"],
            "customer_name": group["name"],
            "campaign": campaign_id,
            "campaign_backfire": campaign_backfire,
            "upgrade": upgrade_id,
            "orders": dict(normalized["orders"]),
            "unit_costs": quote["unit_costs"],
            "products": product_results,
            "demand": total_demand,
            "units_sold": total_sold,
            "stockouts": stockouts,
            "spoilage": spoiled,
            "units_spoiled": total_spoiled,
            "revenue": total_revenue,
            "procurement": quote["procurement"],
            "campaign_cost": quote["campaign_cost"],
            "upgrade_cost": quote["upgrade_cost"],
            "rent": rent,
            "waste_fee": waste_fee,
            "profit": operating_profit,
            "cash_before": cash_before,
            "cash_after": int(self.state["cash"]),
            "reputation_delta": actual_rep_delta,
            "reputation_after": self.state["reputation"],
            "fulfillment": round(fulfillment, 3),
            "achievements": unlocked,
            "achievement_cash": achievement_cash,
            "achievement_reputation": achievement_reputation,
            "flavor": flavor,
        }
        terminal = self.terminal_summary() if self.state["done"] else None
        if terminal:
            report["terminal"] = terminal
        self.state["history"].append(copy.deepcopy(report))
        if not self.state["done"]:
            self.state["day"] += 1
        reward = round(operating_profit + actual_rep_delta * 3.0 + total_sold * 0.25, 3)
        return {
            "observation": self.observation(),
            "reward": reward,
            "terminated": bool(self.state["done"]),
            "report": report,
            "state_digest": self.state_digest(),
        }

    def _inventory_observation(self, product_id: str) -> dict[str, Any]:
        life = self.shelf_life(product_id)
        batches = []
        for batch in self.state["inventory"][product_id]:
            days_left = None if life is None else max(0, life - int(batch["age"]))
            batches.append(
                {
                    "quantity": int(batch["quantity"]),
                    "age": int(batch["age"]),
                    "days_left": days_left,
                }
            )
        return {"units": self.inventory_count(product_id), "batches": batches}

    def demand_forecast(
        self,
        product_id: str,
        *,
        price: int | None = None,
        campaign_id: str | None = None,
        levels: dict[str, int] | None = None,
    ) -> dict[str, int]:
        selected_price = self.state["prices"][product_id] if price is None else price
        midpoint = self._demand_for(
            product_id,
            selected_price,
            campaign_id=campaign_id,
            include_noise=False,
            levels=levels,
        )
        insight = self._effect_sum("forecast_days", levels)
        uncertainty = max(0.08, 0.34 - insight * 0.055)
        return {
            "at_price": selected_price,
            "low": max(0, int(math.floor(midpoint * (1.0 - uncertainty)))),
            "mid": midpoint,
            "high": int(math.ceil(midpoint * (1.0 + uncertainty))),
        }

    def _upcoming_market(self) -> list[dict[str, Any]]:
        event_reveal = int(round(self._effect_sum("event_forecast")))
        demand_reveal = int(round(self._effect_sum("forecast_days")))
        horizon = min(4, max(event_reveal, demand_reveal))
        previews: list[dict[str, Any]] = []
        for offset in range(1, horizon + 1):
            day = self.state["day"] + offset
            if day > self.state["total_days"]:
                break
            preview: dict[str, Any] = {"day": day}
            if offset <= event_reveal:
                event = self.event_at(day)
                preview["event"] = {
                    "id": event["id"],
                    "name": event["name"],
                    "headline": event["headline"],
                    "effects": copy.deepcopy(event["effects"]),
                }
            if offset <= demand_reveal:
                group = self.group_at(day)
                preview["customer_group"] = {
                    "id": group["id"],
                    "name": group["name"],
                    "preferred_tags": list(group["preferred_tags"]),
                }
            previews.append(preview)
        return previews

    def action_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "orders": {
                    "type": "object",
                    "description": "Non-negative integer units to buy before opening.",
                    "product_ids": list(self.product_ids),
                },
                "prices": {
                    "type": "object",
                    "description": "Integer sale prices; omitted products keep their price.",
                    "bounds": {
                        product_id: list(self.price_bounds(product_id))
                        for product_id in self.product_ids
                    },
                },
                "campaign": {"enum": [None, *self.campaigns]},
                "upgrade": {"enum": [None, *self.upgrades]},
            },
            "example": {
                "orders": {product_id: 2 for product_id in self.product_ids},
                "prices": dict(self.state["prices"]),
                "campaign": None,
                "upgrade": None,
            },
        }

    def observation(self) -> dict[str, Any]:
        event = self.event_at()
        group = self.group_at()
        capacity = self.capacity()
        available_upgrades = []
        for upgrade_id, upgrade in self.upgrades.items():
            level = self.state["upgrade_levels"][upgrade_id]
            max_level = int(upgrade["max_level"])
            available_upgrades.append(
                {
                    "id": upgrade_id,
                    "name": upgrade["name"],
                    "track": upgrade["track"],
                    "description": upgrade["description"],
                    "level": level,
                    "max_level": max_level,
                    "cost": None if level >= max_level else self.upgrade_cost(upgrade_id),
                    "effects": copy.deepcopy(upgrade["effects"]),
                }
            )

        products = {}
        for product_id, product in self.products.items():
            products[product_id] = {
                "name": product["name"],
                "short_name": product["short_name"],
                "description": product["description"],
                "tags": list(product["tags"]),
                "base_cost": int(product["base_cost"]),
                "base_price": int(product["base_price"]),
                "unit_cost_today": self.unit_cost(product_id),
                "price": int(self.state["prices"][product_id]),
                "price_bounds": list(self.price_bounds(product_id)),
                "shelf_life": self.shelf_life(product_id),
                "inventory": self._inventory_observation(product_id),
                "forecast": self.demand_forecast(product_id),
            }

        observation: dict[str, Any] = {
            "game": "starport-market",
            "state_version": STATE_VERSION,
            "seed": self.state["seed"],
            "day": self.state["day"],
            "total_days": self.state["total_days"],
            "days_remaining": max(0, self.state["total_days"] - self.state["day"] + 1),
            "cash": int(self.state["cash"]),
            "reputation": float(self.state["reputation"]),
            "capacity": {
                "used": self.inventory_count(),
                "total": capacity,
                "free": max(0, capacity - self.inventory_count()),
            },
            "market": {
                "event": {
                    "id": event["id"],
                    "name": event["name"],
                    "headline": event["headline"],
                    "description": event["description"],
                    "effects": copy.deepcopy(event["effects"]),
                },
                "customer_group": {
                    "id": group["id"],
                    "name": group["name"],
                    "description": group["description"],
                    "preferred_tags": list(group["preferred_tags"]),
                    "price_sensitivity": float(group["price_sensitivity"]),
                    "loyalty_bias": int(group["loyalty_bias"]),
                },
                "upcoming": self._upcoming_market(),
            },
            "products": products,
            "campaigns": [copy.deepcopy(item) for item in self.content["campaigns"]],
            "upgrades": available_upgrades,
            "achievements": [
                {
                    **copy.deepcopy(item),
                    "value": self._achievement_value(item["metric"]),
                    "completed": item["id"] in self.state["completed_achievements"],
                }
                for item in self.content["achievements"]
            ],
            "last_report": copy.deepcopy(self.state["history"][-1]) if self.state["history"] else None,
            "done": bool(self.state["done"]),
            "ending": self.state["ending"],
            "state_digest": self.state_digest(),
        }
        if self.state["done"]:
            observation["terminal"] = self.terminal_summary()
        return observation

    def terminal_summary(self) -> dict[str, Any]:
        inventory_value = sum(
            self.inventory_count(product_id) * int(self.products[product_id]["base_cost"]) // 2
            for product_id in self.product_ids
        )
        upgrade_levels = sum(self.state["upgrade_levels"].values())
        score = int(
            self.state["cash"]
            + inventory_value
            + self.state["reputation"] * 3
            + upgrade_levels * 28
            + self.state["totals"]["units_sold"] * 2
        )
        if self.state["ending"] == "bankrupt":
            rank = "SPACE DEBRIS"
        elif score >= 4600:
            rank = "ORBIT TYCOON"
        elif score >= 3600:
            rank = "NEON MOGUL"
        elif score >= 2500:
            rank = "STAR TRADER"
        elif score >= 1500:
            rank = "STALL KEEPER"
        else:
            rank = "SPACE DEBRIS"
        return {
            "ending": self.state["ending"],
            "score": score,
            "rank": rank,
            "cash": int(self.state["cash"]),
            "inventory_value": inventory_value,
            "reputation": float(self.state["reputation"]),
            "upgrade_levels": upgrade_levels,
            "achievements_completed": len(self.state["completed_achievements"]),
            "achievements_total": len(self.achievements),
            "totals": copy.deepcopy(self.state["totals"]),
            "flavor": self._choose_flavor("game_over"),
        }
