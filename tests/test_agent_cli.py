from __future__ import annotations

import json
import subprocess
import sys


def test_jsonl_server_reports_errors_without_mutating_state() -> None:
    payload = "\n".join(
        [
            json.dumps({"command": "quote", "action": {"orders": {}, "prices": {}}}),
            json.dumps({"orders": {"not_a_product": 1}}),
            json.dumps({"command": "quit"}),
            "",
        ]
    )
    result = subprocess.run(
        [sys.executable, "-m", "starport_market.agent_cli", "serve", "--seed", "11"],
        input=payload,
        text=True,
        capture_output=True,
        check=True,
        timeout=15,
    )
    packets = [json.loads(line) for line in result.stdout.splitlines()]
    assert packets[0]["type"] == "reset"
    assert packets[1]["type"] == "quote"
    assert packets[1]["state_unchanged"] is True
    assert packets[2]["type"] == "error"
    assert packets[2]["state_unchanged"] is True
    assert packets[3] == {"ok": True, "type": "bye"}
