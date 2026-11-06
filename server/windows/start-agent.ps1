# Starts the agent (server\agent.py) unless it is already running. No window (pythonw).
. "$PSScriptRoot\lib.ps1"
$null = Get-Secret 'agent-token.txt'   # creates the token on first run
$running = Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'python*' -and $_.CommandLine -match 'agent\.py' }
if ($running) { Write-Host 'agent already running'; return }
Start-Process -FilePath $Cfg.python -ArgumentList @('-I', "`"$ServerDir\agent.py`"") -WindowStyle Hidden
Write-Host 'agent started'
