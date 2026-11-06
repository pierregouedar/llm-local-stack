@echo off
rem ==== Stops the stack and frees the VRAM (e.g. before gaming). The agent stays ready for "pcwake". ====
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop.ps1"
pause
