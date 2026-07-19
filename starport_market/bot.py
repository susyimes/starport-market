"""Reference policies that consume only public observations."""

from __future__ import annotations

import random
from typing import Any, Protocol

from .agent_env import StarportEnv


class Policy(Protocol):
    def act(self, observation: dict[str, Any]) -> dict[str, Any]: ...


class HeuristicAgent:
    """A transparent baseline: forecast, protect cash, then buy by margin."""

    UPGRADE_PRIORITY = (
        "demand_oracle",
        "cold_rack",
        "neon_signage",
        "event_wiretap",
        "stasis_crates",
        "loyalist_cards",
        "auto_stockbot",
        "drone_hawker",
        "pocket_warehouse",
    )

    def act(self, observation: dict[str, Any]) -> dict[str, Any]:
        cash = int(observation["cash"])
        day = int(observation["day"])
        products = observation["products"]
        group = observation["market"]["customer_group"]
        preferred = set(group["preferred_tags"])

        upgrade = None
        upgrade_cost = 0
        upgrades = {item["id"]: item for item in observation["upgrades"]}
        if day >= 3 and cash >= 170:
            for upgrade_id in self.UPGRADE_PRIORITY:
                item = upgrades[upgrade_id]
                cost = item["cost"]
                if cost is not None and cost <= min(cash * 0.28, cash - 90):
                    upgrade = upgrade_id
                    upgrade_cost = int(cost)
                    break

        event_effects = observation["market"]["event"]["effects"]
        hot_market = float(event_effects.get("demand_all", 1.0)) >= 1.2 or bool(
            event_effects.get("demand_tags")
        )
        campaign = None
        campaign_cost = 0
        if hot_market and cash - upgrade_cost >= 240:
            choices = sorted(
                observation["campaigns"],
                key=lambda item: (item["cost"], -item["demand_bonus"]),
            )
            for item in choices:
                if item["reputation_risk"] <= 1 and item["cost"] <= (cash - upgrade_cost) * 0.16:
                    campaign = item["id"]
                    campaign_cost = int(item["cost"])
                    break

        prices: dict[str, int] = {}
        candidates: list[tuple[float, str, int, int]] = []
        for product_id, product in products.items():
            base_price = int(product["base_price"])
            low, high = product["price_bounds"]
            preferred_hits = len(set(product["tags"]) & preferred)
            markup = 1.08 + preferred_hits * 0.05
            if float(group["price_sensitivity"]) <= 0.8:
                markup += 0.08
            planned_price = max(low, min(high, int(round(base_price * markup))))
            prices[product_id] = planned_price

            forecast = product["forecast"]
            elasticity = float(group["price_sensitivity"])
            adjusted_demand = max(
                0,
                int(round(forecast["mid"] * (forecast["at_price"] / planned_price) ** elasticity)),
            )
            inventory = int(product["inventory"]["units"])
            shelf_life = product["shelf_life"]
            buffer = 1 if shelf_life is not None and shelf_life <= 3 else 2
            desired = max(0, adjusted_demand + buffer - inventory)
            unit_cost = int(product["unit_cost_today"])
            margin = planned_price - unit_cost
            priority = margin * max(1, adjusted_demand) / max(1, unit_cost)
            if preferred_hits:
                priority *= 1.15
            candidates.append((priority, product_id, desired, unit_cost))

        capacity_left = int(observation["capacity"]["free"])
        budget = max(0, cash - upgrade_cost - campaign_cost - 14)
        orders = {product_id: 0 for product_id in products}
        for _, product_id, desired, unit_cost in sorted(candidates, reverse=True):
            affordable = budget // max(1, unit_cost)
            quantity = max(0, min(desired, capacity_left, affordable))
            orders[product_id] = quantity
            capacity_left -= quantity
            budget -= quantity * unit_cost

        return {
            "orders": orders,
            "prices": prices,
            "campaign": campaign,
            "upgrade": upgrade,
        }


class RandomAgent:
    """A conservative random baseline for comparisons."""

    def __init__(self, seed: int = 0) -> None:
        self.rng = random.Random(seed)

    def act(self, observation: dict[str, Any]) -> dict[str, Any]:
        products = observation["products"]
        free = observation["capacity"]["free"]
        cash = max(0, observation["cash"] - 12)
        orders = {product_id: 0 for product_id in products}
        prices = {}
        ids = list(products)
        self.rng.shuffle(ids)
        for product_id in ids:
            product = products[product_id]
            low, high = product["price_bounds"]
            prices[product_id] = self.rng.randint(max(low, product["base_price"] - 2), min(high, product["base_price"] + 4))
            maximum = min(4, free, cash // product["unit_cost_today"])
            quantity = self.rng.randint(0, maximum) if maximum else 0
            orders[product_id] = quantity
            free -= quantity
            cash -= quantity * product["unit_cost_today"]
        return {"orders": orders, "prices": prices, "campaign": None, "upgrade": None}


def run_episode(seed: int, policy: Policy, *, include_trace: bool = False) -> dict[str, Any]:
    env = StarportEnv(seed=seed)
    observation, _ = env.reset()
    trace: list[dict[str, Any]] = []
    while not observation["done"]:
        action = policy.act(observation)
        observation, reward, terminated, _, info = env.step(action)
        if include_trace:
            trace.append(
                {
                    "day": info["report"]["day"],
                    "action": action,
                    "reward": reward,
                    "report": info["report"],
                }
            )
        if terminated:
            break
    result = {
        "seed": seed,
        "days_played": len(env.game.state["history"]),
        "state_digest": env.game.state_digest(),
        "terminal": env.game.terminal_summary(),
    }
    if include_trace:
        result["trace"] = trace
    return result
