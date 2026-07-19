"""Load and validate the data-only content pack."""

from __future__ import annotations

import json
from functools import lru_cache
from importlib.resources import files
from typing import Any


REQUIRED_COLLECTIONS = {
    "products": 5,
    "customer_groups": 6,
    "events": 18,
    "upgrades": 9,
    "campaigns": 5,
}


def _unique_ids(items: list[dict[str, Any]], label: str) -> None:
    ids = [item.get("id") for item in items]
    if any(not isinstance(item_id, str) or not item_id for item_id in ids):
        raise ValueError(f"{label} contains a missing or invalid id")
    if len(ids) != len(set(ids)):
        raise ValueError(f"{label} contains duplicate ids")


def validate_content(content: dict[str, Any]) -> None:
    for label, expected in REQUIRED_COLLECTIONS.items():
        items = content.get(label)
        if not isinstance(items, list) or len(items) != expected:
            raise ValueError(f"{label} must contain exactly {expected} entries")
        _unique_ids(items, label)

    product_ids = {item["id"] for item in content["products"]}
    for product in content["products"]:
        if product["base_cost"] <= 0 or product["base_price"] <= 0:
            raise ValueError(f"invalid price data for {product['id']}")
        if not isinstance(product.get("tags"), list) or not product["tags"]:
            raise ValueError(f"product {product['id']} needs tags")
        shelf_life = product.get("shelf_life")
        if shelf_life is not None and (not isinstance(shelf_life, int) or shelf_life < 1):
            raise ValueError(f"invalid shelf life for {product['id']}")

    if len(product_ids) != 5:
        raise ValueError("the economy requires five products")

    flavor = content.get("flavor_lines")
    if not isinstance(flavor, dict):
        raise ValueError("flavor_lines must be an object")
    for key in ("sale_success", "stockout", "spoilage", "upgrade", "game_over"):
        if not isinstance(flavor.get(key), list) or not flavor[key]:
            raise ValueError(f"missing flavor line group: {key}")

    achievements = content.get("achievements")
    if not isinstance(achievements, list) or len(achievements) != 10:
        raise ValueError("achievements must contain exactly 10 entries")
    _unique_ids(achievements, "achievements")
    tips = content.get("tutorial_tips")
    if not isinstance(tips, list) or len(tips) != 12:
        raise ValueError("tutorial_tips must contain exactly 12 entries")


@lru_cache(maxsize=1)
def load_content() -> dict[str, Any]:
    resource = files("starport_market").joinpath("data/content.json")
    content = json.loads(resource.read_text(encoding="utf-8"))
    validate_content(content)
    return content
