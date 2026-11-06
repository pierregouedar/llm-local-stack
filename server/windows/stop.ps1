# Stops the stack (llama-swap, llama-server, opencode serve, idle-sleep watchdog) and frees the VRAM.
# The agent keeps running, so the waker can start the stack again on the next "pcwake".
. "$PSScriptRoot\lib.ps1"
Get-StackProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host "stopped: $($_.Name)" }
Log 'stack stopped'
Start-Sleep -Seconds 2
nvidia-smi --query-gpu=memory.used --format=csv,noheader | ForEach-Object { Write-Host "VRAM in use: $_" }
