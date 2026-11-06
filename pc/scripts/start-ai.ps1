# Demarre (ou redemarre) la pile IA :
#   - llama-swap  : <listen>:<llama_swap_port>, cle d'API (config generee depuis le modele)
#   - opencode serve (optionnel, si "opencode" est renseigne dans stack.json) : <listen>:<opencode_port>
#   - la surveillance de veille (idle-sleep.ps1)
# -IfNotRunning     : ne fait rien si la pile tourne deja et repond (utilise par l'agent apres un reveil).
# -KeepAwakeHours N : au lieu de la surveillance de veille, garde le PC eveille N heures.
param([int]$KeepAwakeHours = 0, [switch]$IfNotRunning)

$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\common.ps1"

if ($IfNotRunning) {
  # Apres un reveil, le reseau met quelques secondes a revenir : jusqu'a 60 s avant de conclure.
  $ip = Get-ListenIp 30
  $up = $false
  if (Get-Process llama-swap -ErrorAction SilentlyContinue) {
    for ($i = 0; $i -lt 30 -and -not $up; $i++) {
      try { $null = Invoke-WebRequest "http://${ip}:$($Cfg.llama_swap_port)/health" -UseBasicParsing -TimeoutSec 2; $up = $true }
      catch { if ($_.Exception.Response) { $up = $true } else { Start-Sleep -Seconds 2 } }
    }
  }
  if ($up) { Log 'la pile tourne deja et repond, rien a relancer'; return }
  Log 'pile absente ou muette, relance complete'
}

# Arret de ce qui tourne deja (pas l'agent).
Get-StackProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

$ip = Get-ListenIp

# 1) llama-swap (config regeneree a chaque demarrage)
$yaml = Write-LlamaSwapConfig
Start-Process -FilePath $Cfg.llama_swap -ArgumentList @('--config', "`"$yaml`"", '--listen', "${ip}:$($Cfg.llama_swap_port)") `
  -WorkingDirectory (Split-Path $yaml) -WindowStyle Hidden `
  -RedirectStandardOutput (Join-Path $Logs 'llama-swap.out.log') -RedirectStandardError (Join-Path $Logs 'llama-swap.err.log')
Log "llama-swap demarre sur ${ip}:$($Cfg.llama_swap_port)"

# 2) opencode serve (optionnel : projets sur le PC pilotes a distance avec "opencode attach")
if ($Cfg.opencode) {
  $env:OPENCODE_SERVER_PASSWORD = Get-Secret 'opencode-password.txt'
  if ($Cfg.extra_path) { $env:PATH = "$($Cfg.extra_path);$env:PATH" }
  Start-Process -FilePath $Cfg.opencode -ArgumentList @('serve', '--hostname', $ip, '--port', $Cfg.opencode_port) `
    -WorkingDirectory $env:USERPROFILE -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $Logs 'opencode.out.log') -RedirectStandardError (Join-Path $Logs 'opencode.err.log')
  Log "opencode serve demarre sur ${ip}:$($Cfg.opencode_port)"
}

# 3) surveillance de veille, ou maintien en eveil temporaire
if ($KeepAwakeHours -gt 0) {
  Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSScriptRoot\keep-awake.ps1`"", '-Hours', $KeepAwakeHours) -WindowStyle Hidden
  Log "maintien en eveil pendant $KeepAwakeHours h"
} else {
  Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSScriptRoot\idle-sleep.ps1`"") -WindowStyle Hidden
  Log "surveillance de veille demarree ($($Cfg.idle_sleep_minutes) min)"
}
