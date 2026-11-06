@echo off
rem ==== Arrete la pile IA et libere la VRAM (mode jeu). L'agent reste pret pour "pcwake". ====
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stop-ai.ps1"
pause
