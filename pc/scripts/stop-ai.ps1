# Arrete la pile IA (llama-swap, llama-server, opencode serve, surveillance de veille) et libere la VRAM.
# L'agent reste actif : le NAS pourra relancer la pile au prochain "pcwake".
. "$PSScriptRoot\common.ps1"
Get-StackProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host "arrete : $($_.Name)" }
Log 'pile arretee'
Start-Sleep -Seconds 2
nvidia-smi --query-gpu=memory.used --format=csv,noheader | ForEach-Object { Write-Host "VRAM utilisee : $_" }
