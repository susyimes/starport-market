"""JSON command-line protocol for non-visual agents."""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from typing import Any

from .agent_env import StarportEnv
from .bot import HeuristicAgent, RandomAgent, run_episode
from .core import InvalidAction


def _emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)


def serve(seed: int) -> int:
    env = StarportEnv(seed=seed)
    observation, info = env.reset()
    _emit(
        {
            "ok": True,
            "type": "reset",
            "observation": observation,
            "action_schema": info["action_schema"],
        }
    )
    for line_number, line in enumerate(sys.stdin, start=1):
        if not line.strip():
            continue
        digest_before = env.game.state_digest()
        try:
            request = json.loads(line)
            if not isinstance(request, dict):
                raise InvalidAction("request must be an object")
            command = request.get("command")
            if command == "reset":
                observation, info = env.reset(seed=int(request.get("seed", seed)))
                _emit(
                    {
                        "ok": True,
                        "type": "reset",
                        "observation": observation,
                        "action_schema": info["action_schema"],
                    }
                )
                continue
            if command == "observe":
                _emit({"ok": True, "type": "observation", "observation": env.render()})
                continue
            if command == "quote":
                quote = env.game.quote_action(request.get("action", {}))
                _emit(
                    {
                        "ok": True,
                        "type": "quote",
                        "quote": quote,
                        "state_unchanged": digest_before == env.game.state_digest(),
                        "state_digest": env.game.state_digest(),
                    }
                )
                continue
            if command == "quit":
                _emit({"ok": True, "type": "bye"})
                return 0

            action = request.get("action", request)
            observation, reward, terminated, truncated, info = env.step(action)
            _emit(
                {
                    "ok": True,
                    "type": "transition",
                    "observation": observation,
                    "reward": reward,
                    "terminated": terminated,
                    "truncated": truncated,
                    "info": info,
                }
            )
        except (json.JSONDecodeError, InvalidAction, TypeError, ValueError) as exc:
            _emit(
                {
                    "ok": False,
                    "type": "error",
                    "line": line_number,
                    "error": str(exc),
                    "state_unchanged": digest_before == env.game.state_digest(),
                    "state_digest": env.game.state_digest(),
                }
            )
    return 0


def autoplay(seed: int, episodes: int, policy_name: str, trace: bool) -> int:
    results = []
    for offset in range(episodes):
        episode_seed = seed + offset
        policy = HeuristicAgent() if policy_name == "heuristic" else RandomAgent(episode_seed)
        results.append(run_episode(episode_seed, policy, include_trace=trace))
    scores = [item["terminal"]["score"] for item in results]
    payload: dict[str, Any] = {
        "policy": policy_name,
        "episodes": episodes,
        "seed_start": seed,
        "score_min": min(scores),
        "score_median": statistics.median(scores),
        "score_max": max(scores),
        "runs": results,
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="starport-agent",
        description="Deterministic JSON interface for Starport Market agents.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    schema_parser = subparsers.add_parser("schema", help="Print the action schema and initial observation.")
    schema_parser.add_argument("--seed", type=int, default=7)

    serve_parser = subparsers.add_parser("serve", help="Run a JSON-lines episode on stdin/stdout.")
    serve_parser.add_argument("--seed", type=int, default=7)

    auto_parser = subparsers.add_parser("autoplay", help="Run reference-agent episodes.")
    auto_parser.add_argument("--seed", type=int, default=7)
    auto_parser.add_argument("--episodes", type=int, default=1)
    auto_parser.add_argument("--policy", choices=("heuristic", "random"), default="heuristic")
    auto_parser.add_argument("--trace", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "schema":
        env = StarportEnv(seed=args.seed)
        observation, info = env.reset()
        print(
            json.dumps(
                {"action_schema": info["action_schema"], "observation": observation},
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    if args.command == "serve":
        return serve(args.seed)
    if args.command == "autoplay":
        return autoplay(args.seed, args.episodes, args.policy, args.trace)
    raise AssertionError("unreachable")


if __name__ == "__main__":
    raise SystemExit(main())
