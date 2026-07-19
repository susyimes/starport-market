from __future__ import annotations

import copy
import json
import statistics

import pytest

from starport_market.agent_env import StarportEnv
from starport_market.bot import HeuristicAgent, RandomAgent, run_episode
from starport_market.content import load_content, validate_content
from starport_market.core import InvalidAction, MarketGame


def basic_action(game: MarketGame, quantity: int = 1) -> dict:
    return {
        "orders": {product_id: quantity for product_id in game.product_ids},
        "prices": dict(game.state["prices"]),
        "campaign": None,
        "upgrade": None,
    }


def test_content_pack_is_complete_and_ascii_safe() -> None:
    content = load_content()
    validate_content(content)
    assert [len(content[key]) for key in ("products", "customer_groups", "events", "upgrades", "campaigns")] == [5, 6, 18, 9, 5]
    for collection in ("products", "customer_groups", "events", "upgrades", "campaigns"):
        for item in content[collection]:
            item["name"].encode("ascii")


def test_same_seed_state_and_action_are_bitwise_deterministic() -> None:
    first = MarketGame(seed=42)
    second = MarketGame(seed=42)
    assert first.state_digest() == second.state_digest()
    first_result = first.step(basic_action(first, 2))
    second_result = second.step(basic_action(second, 2))
    assert first_result == second_result


def test_export_reload_preserves_next_transition() -> None:
    game = MarketGame(seed=17)
    game.step(basic_action(game, 1))
    restored = MarketGame.from_state(game.export_state())
    action = basic_action(game, 0)
    assert restored.state_digest() == game.state_digest()
    assert restored.step(action) == game.step(action)


def test_invalid_action_is_atomic() -> None:
    game = MarketGame(seed=7)
    digest = game.state_digest()
    action = basic_action(game, 99)
    with pytest.raises(InvalidAction, match="capacity exceeded"):
        game.step(action)
    assert game.state_digest() == digest


def test_price_bounds_and_maxed_upgrades_are_atomic() -> None:
    game = MarketGame(seed=12)
    digest = game.state_digest()
    action = basic_action(game, 0)
    action["prices"]["holo_charm"] = 999
    with pytest.raises(InvalidAction, match="price for holo_charm"):
        game.step(action)
    assert game.state_digest() == digest

    game.state["upgrade_levels"]["pocket_warehouse"] = 1
    digest = game.state_digest()
    action = basic_action(game, 0)
    action["upgrade"] = "pocket_warehouse"
    with pytest.raises(InvalidAction, match="already maxed"):
        game.step(action)
    assert game.state_digest() == digest


def test_plan_quote_changes_with_price_and_never_mutates_state() -> None:
    game = MarketGame(seed=21)
    digest = game.state_digest()
    low_action = basic_action(game, 1)
    high_action = copy.deepcopy(low_action)
    low, high = game.price_bounds("glow_noodles")
    low_action["prices"]["glow_noodles"] = low
    high_action["prices"]["glow_noodles"] = high
    low_quote = game.quote_action(low_action)
    high_quote = game.quote_action(high_action)
    assert low_quote["demand_forecasts"]["glow_noodles"]["mid"] > high_quote["demand_forecasts"]["glow_noodles"]["mid"]
    assert set(low_quote["estimated_revenue"]) == {"low", "mid", "high"}
    assert game.state_digest() == digest

def test_temporary_capacity_drop_does_not_softlock_existing_stock() -> None:
    game = MarketGame(seed=1)
    game.state["event_schedule"][0] = "freezer_meltdown"
    game.state["inventory"]["meteor_jerky"] = [{"quantity": 20, "age": 0}]
    action = basic_action(game, 0)
    quote = game.quote_action(action)
    assert quote["projected_units"] == 20
    assert quote["projected_capacity"] == 18
    game.step(action)


def test_perishables_age_and_create_real_waste_risk() -> None:
    game = MarketGame(seed=3)
    game.state["event_schedule"][0] = "quiet_orbit"
    game.state["group_schedule"][0] = "dock_workers"
    game.state["inventory"]["glow_noodles"] = [{"quantity": 24, "age": 1}]
    action = basic_action(game, 0)
    action["prices"]["glow_noodles"] = game.price_bounds("glow_noodles")[1]
    transition = game.step(action)
    assert transition["report"]["spoilage"]["glow_noodles"] > 0
    assert transition["report"]["waste_fee"] > 0


def test_inventory_sales_are_fifo_by_batch() -> None:
    game = MarketGame(seed=4)
    game.state["inventory"]["plasma_fruit"] = [
        {"quantity": 2, "age": 2},
        {"quantity": 5, "age": 0},
    ]
    assert game._sell("plasma_fruit", 3) == 3
    assert game.state["inventory"]["plasma_fruit"] == [{"quantity": 4, "age": 0}]


def test_storage_upgrade_can_expand_same_day_plan() -> None:
    game = MarketGame(seed=5)
    game.state["cash"] = 1000
    game.state["event_schedule"][0] = "quiet_orbit"
    action = basic_action(game, 0)
    action["orders"]["glow_noodles"] = 25
    action["upgrade"] = "cold_rack"
    quote = game.quote_action(action)
    assert quote["projected_capacity"] == 32
    assert quote["projected_units"] == 25


def test_milestones_unlock_once_and_pay_visible_rewards() -> None:
    game = MarketGame(seed=6)
    game.state["totals"]["units_sold"] = 25
    cash_before = game.state["cash"]
    transition = game.step(basic_action(game, 0))
    unlocked = transition["report"]["achievements"]
    assert [item["id"] for item in unlocked] == ["first_sale"]
    assert transition["report"]["achievement_cash"] == 10
    assert game.state["cash"] >= cash_before - transition["report"]["rent"] + 10
    game.step(basic_action(game, 0))
    assert "first_sale" not in [
        item["id"] for item in game.state["history"][-1]["achievements"]
    ]


def test_bankruptcy_and_final_day_are_terminal_without_day_nineteen() -> None:
    bankrupt = MarketGame(seed=2)
    bankrupt.state["cash"] = 0
    transition = bankrupt.step(basic_action(bankrupt, 0))
    assert transition["terminated"] is True
    assert transition["report"]["terminal"]["ending"] == "bankrupt"

    finale = MarketGame(seed=8)
    finale.state["day"] = 18
    transition = finale.step(basic_action(finale, 0))
    assert transition["terminated"] is True
    assert finale.state["day"] == 18
    assert transition["report"]["terminal"]["ending"] == "completed"
    assert "zero_waste_run" in finale.state["completed_achievements"]


def test_agent_environment_uses_json_safe_gym_style_contract() -> None:
    env = StarportEnv(seed=9)
    observation, info = env.reset()
    json.dumps(observation)
    json.dumps(info)
    action = HeuristicAgent().act(observation)
    result = env.step(action)
    assert len(result) == 5
    next_observation, reward, terminated, truncated, step_info = result
    assert isinstance(reward, float)
    assert terminated is False
    assert truncated is False
    json.dumps(next_observation)
    json.dumps(step_info)


def test_reference_agent_completes_every_seed_and_beats_random_baseline() -> None:
    heuristic_scores = []
    random_scores = []
    for seed in range(10, 20):
        smart = run_episode(seed, HeuristicAgent())
        random_run = run_episode(seed, RandomAgent(seed))
        assert smart["days_played"] == 18
        assert smart["terminal"]["ending"] == "completed"
        heuristic_scores.append(smart["terminal"]["score"])
        random_scores.append(random_run["terminal"]["score"])
    assert statistics.median(heuristic_scores) > statistics.median(random_scores) + 1200
    assert min(heuristic_scores) >= 3000
