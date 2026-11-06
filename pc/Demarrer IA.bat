@echo off
rem ==== Demarre la pile IA locale (a lancer une fois apres un redemarrage du PC) ====
rem 1. l'agent (permet au NAS de relancer la pile apres un reveil)
rem 2. llama-swap (+ opencode serve si configure) + surveillance de veille
rem Configuration : pc\stack.json (copie de pc\stack.example.json).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-agent.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-ai.ps1"
powershell -NoProfile -Command "Start-Sleep 3; if (Get-Process llama-swap -ErrorAction SilentlyContinue) { Write-Host 'IA locale demarree.' } else { Write-Host 'Echec : voir le dossier pc\logs' }"
pause
