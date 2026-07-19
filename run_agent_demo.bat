@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo [Starport Market] Creating local Python environment...
  python -m venv .venv || exit /b 1
  .venv\Scripts\python.exe -m pip install -e . || exit /b 1
)
.venv\Scripts\python.exe -m starport_market.agent_cli autoplay --seed 7 --episodes 10
