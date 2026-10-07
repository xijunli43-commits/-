@echo off
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  python -m venv .venv
  .venv\Scripts\python.exe -m pip install -r requirements.txt
  if errorlevel 1 (
    pause
    exit /b 1
  )
)
echo Read-only catalog will be available on your local network.
echo Administration remains localhost-only.
ipconfig
start "" "http://127.0.0.1:8765/"
.venv\Scripts\python.exe run.py --lan
pause
