"""Small Gym-like facade for tool-using and learning agents."""

from __future__ import annotations

import copy
from typing import Any

from .core import MarketGame


class StarportEnv:
    """A dependency-free agent environment.

    The API intentionally resembles the useful part of Gymnasium without
    requiring NumPy or Gymnasium. Observations and actions are plain JSON-safe
    dictionaries.
    """

    metadata = {
        "name": "starport-market-v1",
        "render_modes": ["json"],
        "deterministic": True,
    }

    def __init__(self, seed: int = 7) -> None:
        self.seed = int(seed)
        self.game = MarketGame(seed=self.seed)

    def reset(self, *, seed: int | None = None) -> tuple[dict[str, Any], dict[str, Any]]:
        if seed is not None:
            self.seed = int(seed)
        self.game = MarketGame(seed=self.seed)
        observation = self.game.observation()
        info = {
            "action_schema": self.game.action_schema(),
            "state_digest": self.game.state_digest(),
        }
        return observation, info

    def step(
        self, action: dict[str, Any]
    ) -> tuple[dict[str, Any], float, bool, bool, dict[str, Any]]:
        transition = self.game.step(copy.deepcopy(action))
        info = {
            "report": transition["report"],
            "state_digest": transition["state_digest"],
        }
        return (
            transition["observation"],
            float(transition["reward"]),
            bool(transition["terminated"]),
            False,
            info,
        )

    @property
    def action_schema(self) -> dict[str, Any]:
        return self.game.action_schema()

    def export_state(self) -> dict[str, Any]:
        return self.game.export_state()

    def load_state(self, state: dict[str, Any]) -> dict[str, Any]:
        self.game = MarketGame.from_state(copy.deepcopy(state))
        self.seed = int(self.game.state["seed"])
        return self.game.observation()

    def render(self) -> dict[str, Any]:
        return self.game.observation()
