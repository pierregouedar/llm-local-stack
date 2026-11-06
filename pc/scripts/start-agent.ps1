# Lance l'agent (ia-agent.py) s'il ne tourne pas deja. Sans fenetre (pythonw).
. "$PSScriptRoot\common.ps1"
$null = Get-Secret 'agent-token.txt'   # cree le jeton au premier lancement
$running = Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'python*' -and $_.CommandLine -match 'ia-agent\.py' }
if ($running) { Write-Host 'agent deja actif'; return }
Start-Process -FilePath $Cfg.pythonw -ArgumentList @('-I', "`"$PSScriptRoot\ia-agent.py`"") -WindowStyle Hidden
Write-Host 'agent demarre'
