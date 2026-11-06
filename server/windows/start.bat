@echo off
rem ==== Starts the local LLM stack (run once after a reboot) ====
rem 1. the agent (lets the waker restart the stack after a wake-up)
rem 2. llama-swap (+ opencode serve if configured) + idle-sleep watchdog
rem Configuration: server\config.json (copy of server\config.example.json).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-agent.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
powershell -NoProfile -Command "Start-Sleep 3; if (Get-Process llama-swap -ErrorAction SilentlyContinue) { Write-Host 'Local LLM stack started.' } else { Write-Host 'Failed: see server\logs' }"
pause
