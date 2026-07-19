# Agent instructions

Starport Market has one deterministic economy shared by humans and agents.

- Keep all business rules in `starport_market/core.py`; the Pyxel UI may present
  state but must not own alternate prices, demand, rewards, or inventory rules.
- Keep the core and `agent_env.py` free of Pyxel, NumPy, Gymnasium, wall-clock
  time, network access, and unseeded randomness.
- Any observation used by the reference bot must remain JSON serializable.
- Invalid actions must be atomic: validate the whole plan before mutating state.
- Content belongs in `starport_market/data/content.json`; preserve stable IDs.
- UI-facing names must stay ASCII because the default Pyxel font is used.
- Add or update tests for rule changes and run `.venv\Scripts\python -m pytest`.
- A gameplay change is not complete until both a full Agent episode and a real
  Pyxel launch succeed.
